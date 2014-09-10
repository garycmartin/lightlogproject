#!/usr/local/bin/python
# coding=UTF-8
# Tested with Python 2.7
# Requires installation of the pyserial python module

# Copyright (c) 2013, 2014, Gary C. Martin <gary@lightlogproject.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

"""Download and convert data from a Light Log <http://lightlogproject.org>.

Raw data bytes are downloaded from a Light Log device through a serial port and
saved as a CSV file for easy processing with external tools. Time stamps use
calculations based on the local systems time, so be aware your local clock
should be reasonable accurate when downloading.
"""

import platform
import sys
import time
import math
import datetime
import argparse
import serial
from serial.tools import list_ports

#SERIAL_BAUD = 38400
SERIAL_BAUD = 19200
STEP_SECONDS = 60 # default grab from status 'Period' if available
VERSION = 'v0.11'

def get_args():
    """\
    Parse and return command line arguments.
    """
    parser = argparse.ArgumentParser(description='Download, convert and save data from Light Log device. Without arguments data will be saved to an auto-named csv file Light_Log_<device_ID>.csv in the current directory, if the log file already exists, new data will be appended to the log.')

    parser.add_argument("-p", "--port",
                        help="serial or COM port name")
    parser.add_argument("-r", "--raw",
                        help="raw 10-bit sensor data, no conversion to lux scale",
                        action="store_true")
    parser.add_argument("-b", "--both",
                        help="auto saves two files, raw 10-bit sensor data and one in lux",
                        action="store_true")
    parser.add_argument("--csv-header",
                        help="outputs column header in first row of data",
                        action="store_true")
    parser.add_argument("-v", "--version",
                        help="show download software version number and exit",
                        action="store_true")

    group = parser.add_mutually_exclusive_group()
    group.add_argument("-f", "--file",
                       help="save downloaded data to a named file")
    group.add_argument("--stdout",
                       help="send data to console std out",
                       action="store_true")
    group.add_argument("--cmd",
                       help="device command: a=display device status data; e=reset memory pointer (for a fresh logging session); f=zero reboot counter (for hardware debugging); l=zero daily light goal; m=zero day phase (define now as peak sleep point); n=half day phase (define + 12hrs as peak sleep point); z=trigger device first boot init (!!!).",
                       choices=['a', 'e', 'f', 'l', 'm', 'n', 'z'])
    group.add_argument("--cal",
                       help="calibrate hardware to known lux light sources",
                       choices=['2.5k', '5k', '10k'])

    if parser.parse_args().version:
        print >> sys.stderr, "Version", VERSION
        sys.exit(0)

    return parser.parse_args()

def get_serial_ports():
    """\
    Return generator for available serial ports.
    """
    if platform.system() == 'Windows':
        # Windows
        for i in range(256):
            try:
                s = serial.Serial(i)
                s.close()
                yield 'COM' + str(i + 1)
            except serial.SerialException:
                pass
    else:
        # Unix
        for port in list_ports.comports():
            yield port[0]

def find_and_return_custom_cable():
    """\
    Search for a serial port matching the custom PICAXE cable name.
    """
    for p in serial.tools.list_ports.comports():
        if 'PICAXE' in p[1]:
            return p[0]
    return None

def parse_status_header(status):
    """\
    Extract data from Light Log status header, returning a dictionary.
    """
    status_list = [i.split(':') for i in status.split(';')]
    status_dict = dict(zip([i[0] for i in status_list], [i[1] for i in status_list]))

    # Break out the individual R, G, B, and W values into a list
    status_dict['RGBW'] = map(int, status_dict['RGBW'].split(','))

    # Make a nice hex string of the two word unique ID
    status_dict['ID'] = '%0.4X%0.4X' % (int(status_dict['ID'].split(',')[0]),
                                        int(status_dict['ID'].split(',')[1]))

    # Battery output in mV
    status_dict['Batt'] = int(status_dict['Batt'][:-2])

    # Convert relavent strings to int
    for i in ('Goal', 'FW', '10KluxB', '5KluxB', '5KluxG', '5KluxR', '5KluxW',
              'Phase', '2.5KluxG','2.5KluxB','HW', '2.5KluxW','2.5KluxR', 'Period',
              '10KluxG', 'Boots', 'Wrap', '10KluxW', 'Pointer', '10KluxR', 'Batt'):
        if i in status_dict:
            status_dict[i] = int(status_dict[i])
    return status_dict

def convert_to_lux(red, green, blue, white, status_dict):
    """\
    Use pre-fitted average lux test data function to convert to lux.

    Ideally this function should use the current devices calibration data
    status_dict['2.5KluxW'], status_dict['5KluxW'], status_dict['10KluxW'],
    etc to convert sensor data to lux. Currently this function has been
    pre-fitted to average calibration data from multiple devices.
        RGB values are scaled relative to the clear sensor lux value as an
    estimate for how much each section of the spectra may map into the
    total lux value (lux is a measurement of the total visible spectrum EMF).
    RGB values are not (yet) calibrated to a set of known colour sources.
    """

    r = float('%.4f' % linear_interpolation(red))
    g = float('%.4f' % linear_interpolation(green))
    b = float('%.4f' % linear_interpolation(blue))
    w = float('%.4f' % linear_interpolation(white))

    return r, g, b, w


def linear_interpolation(x):
    """\
    Linear interpolation between recorded data point values.
    """
    calibration_data =  [(0,0), (1, 28), (10, 60), (50, 213), (100, 296), (200, 406), (300, 461), (500, 531), (1000, 633), (2500, 794), (5000, 838), (10000, 862), (20000, 887), (54000, 902), (58000, 903), (60000, 904), (66000, 905), (80000, 908), (85000, 909), (116000, 917), (200000, 1023)]
    calibration_data.reverse()
    x = float(x)
    result = None
    old_pair = None
    for pair in calibration_data:
        if x >= pair[1] and old_pair:
            result = (x - pair[1]) / (old_pair[1] - pair[1]) * (old_pair[0] - pair[0]) + pair[0]
            break
        old_pair = pair

    return result

def inverse_harris(x):
    """\
    Curve fitted lux function http://zunzun.com/Equation/2/YieldDensity/InverseHarris/
    """
    x = float(x)
    a = -1.0418515764334417E+00
    b = 1.4647346407912545E+02
    c = -7.2246864466197369E-01
    return x / (a + b * x ** c)

def ramberg_osgood_fit(x):
    """\
    Curve fitted lux function http://zunzun.com/Equation/2/Engineering/Ramberg-Osgood/
    """
    x = float(x)
    youngs_modulus = 1.9765780295845900E-01
    k = 7.4474601294925719E+02
    n = 1.9137962029987306E-02
    return (x / youngs_modulus) + (x / k) ** (1.0 / n)

def exponential_fit(x):
    """\
    Curve fitted lux function http://zunzun.com/Equation/2/Exponential/Exponential/
    """
    x = float(x)
    a = 2.1242230658871749E-15
    b = 4.8842737652298622E-02
    return a * math.exp(b * x)

def download_data_from_lightlog(ser, args):
    """\
    Download data from serial connection with Light Log.
    """
    wait_time = 10
    timer = time.time()
    message_update = 2048
    communication_phase = 0
    data = ''
    seconds_now = None
    expect_data = True

    while True:
        time.sleep(0.001) # free up some cpu
        if data[-8:] == 'data_eof':
            # Data downloaded
            break

        if time.time() - timer > wait_time or not expect_data:
            # Give up waiting
            break

        raw_data = ser.read(256)
        if len(raw_data) > 0:
            data += raw_data
            timer = time.time()
            wait_time = 1

            if data[-6:] == 'Hello?':
                data = ''
                expect_data = False

                if communication_phase == 0:
                    if args.cmd == 'a':
                        ser.write('a') # a = request status output
                        expect_data = True
                    elif args.cmd == 'e':
                        ser.write('e') # e = reset mem pointer!
                    elif args.cmd == 'f':
                        ser.write('f') # f = reset reboot counter
                    elif args.cal == '2.5k':
                        ser.write('h') # h = calibrate to 2.5K lux source!!
                    elif args.cal == '5k':
                        ser.write('i') # i = calibrate to 5K lux source!!
                    elif args.cal == '10k':
                        ser.write('j') # j = calibrate to 10K lux source!!
                    elif args.cmd == 'l':
                        ser.write('l') # l = zero light goal
                    elif args.cmd == 'm':
                        ser.write('m') # m = zero day phase (peak sleep point)
                    elif args.cmd == 'n':
                        ser.write('n') # n = half day phase (peak sleep point + half day)
                    elif args.cmd == 'z':
                        ser.write('z') # z = first boot init (but not leave calibration alone)!
                    else:
                        ser.write('c') # c = download
                        expect_data = True
                    communication_phase = 1
                    sys.stdout.write('Communicating with Light Log.')
                    sys.stdout.flush()
                    # Grab current time now
                    seconds_now = int((datetime.datetime.now() -
                                  datetime.datetime(1970,1,1,0,0)).total_seconds())

            if len(data) > message_update:
                message_update += 2048
                sys.stdout.write('.')
                sys.stdout.flush()

    if communication_phase == 1:
        print >> sys.stderr

    return data, seconds_now, expect_data

def extract_data(data, args, seconds_now, status_dict):
    """\
    Parse raw byte data block and return a list of row light data.
    """
    data = data[:-8]
    data_rows = []
    seconds = seconds_now - (len(data) / 6 * STEP_SECONDS)
    for i in range(0, len(data), 6):

        r = ord(data[i]) + ((ord(data[i + 4]) & 0b11) * 256)
        g = ord(data[i + 1]) + ((ord(data[i + 4]) & 0b1100) * 64)
        b = ord(data[i + 2]) + ((ord(data[i + 4]) & 0b110000) * 16)
        w = ord(data[i + 3]) + ((ord(data[i + 4]) & 0b11000000) * 4)

        flags = ord(data[i + 5]) >> 6
        # 11 = reboot
        # 01 = blocked sensors
        # 10 = button press
        # 00 = OK

        # Raw sensor data
        data_rows.append([r, g, b, w, seconds, flags])
        seconds += STEP_SECONDS

    return data_rows

def append_data_to_file(data_rows, args, status_dict):
    """\
    Append data to the end of an existing log file, or create a new file if none exists.
    """
    try:
        f = open(args.file, "rb")
    except IOError:
        # File does not exist so switch to creating a new file
        output_data_to_file(data_rows, args, status_dict)
    else:
        last_log_end = get_timestamp_from_end_of_file(f)
        time_correct = last_log_end
        count_rows = 0
        f.close()

        f = open(args.file, "a")
        if data_rows[0][4] > last_log_end:
            print >> sys.stderr, "WARNING: %dmin gap between this and existing log data." % (int((data_rows[0][4] - last_log_end) / 60.0))
            for row in data_rows:
                f.write("%s,%s,%s,%s,%s,%s\n" % raw_or_lux_output(row, args, status_dict))
                count_rows += 1

        else:
            # Append only newer data than existing log
            for row in data_rows:
                if row[4] > last_log_end:
                    time_correct += STEP_SECONDS
                    row[4] = time_correct
                    f.write("%s,%s,%s,%s,%s,%s\n" % raw_or_lux_output(row, args, status_dict))
                    count_rows += 1
        f.close()

        print >> sys.stderr, "Appended", count_rows,
        print >> sys.stderr, "samples to %s from Light Log ID %s." % (args.file, status_dict['ID'])


def get_timestamp_from_end_of_file(f):
    f.seek(-2, 2)
    while f.read(1) != "\n":
        f.seek(-2, 1)
    return int(f.readline().split(',')[4])


def output_data_to_file(data_rows, args, status_dict):
    """\
    Output data rows to file, will overwrite if file already exists.
    """
    f = open(args.file, "w")

    if args.csv_header:
        f.write("red,green,blue,white,epoch,flags\n")

    for row in data_rows:
        f.write("%s,%s,%s,%s,%s,%s\n" % raw_or_lux_output(row, args, status_dict))
    f.close()

    print >> sys.stderr, "Wrote", len(data_rows),
    print >> sys.stderr, "samples to %s from Light Log ID %s." % (args.file, status_dict['ID'])


def output_data_to_stdout(data_rows, args, status_dict):
    """\
    Output data rows to std out.
    """
    if args.csv_header:
        print "red,green,blue,white,epoch,flags"

    for row in data_rows:
        print "%s,%s,%s,%s,%s,%s" % raw_or_lux_output(row, args, status_dict)

    print >> sys.stderr, "Downloaded", len(data_rows),
    print >> sys.stderr, "samples from Light Log ID %s." % (status_dict['ID'])


def raw_or_lux_output(row, args, status_dict):
    """\
    Process raw red, green, blue, white data to lux if needed.
    """
    if args.raw:
        # Raw sensor data
        return (row[0], row[1], row[2], row[3], row[4], row[5])

    else:
        r, g, b, w = convert_to_lux(row[0], row[1], row[2], row[3], status_dict)
        return (r, g, b, w, row[4], row[5])


def main():
    args = get_args()

    if args.port:
        serial_ports = [args.port]
    else:
        serial_ports = [find_and_return_custom_cable()]
        if serial_ports == [None]:
            serial_ports = list(get_serial_ports())[::-1]

    if len(serial_ports) == 0:
        print >> sys.stderr, "No serial devices available."
        sys.exit(1)

    for port in serial_ports:
        try:
            # Open serial connection
            ser = serial.Serial(port, SERIAL_BAUD, timeout=0)

        except (OSError, IOError):
            pass

        else:
            print >> sys.stderr, "Trying %s (press Light Log button)." % port
            data, seconds_now, expect_data = download_data_from_lightlog(ser, args)
            ser.close()
            if len(data) > 0 or not expect_data:
                break

    if data[-8:] == 'data_eof':
        # Strip off status head from data
        status, data = data.split('head_eof')
        status_dict = parse_status_header(status)

        data_rows = extract_data(data, args, seconds_now, status_dict)

        if args.stdout:
            output_data_to_stdout(data_rows, args, status_dict)

        else:
            if not args.file:
                if args.both:
                    args.raw = True
                    args.file = 'Light_Log_%s_raw.csv' % (status_dict['ID'])
                    append_data_to_file(data_rows, args, status_dict)
                    args.raw = None
                    args.file = 'Light_Log_%s.csv' % (status_dict['ID'])
                    append_data_to_file(data_rows, args, status_dict)

                elif args.raw:
                    args.file = 'Light_Log_%s_raw.csv' % (status_dict['ID'])
                    append_data_to_file(data_rows, args, status_dict)

                else:
                    args.file = 'Light_Log_%s.csv' % (status_dict['ID'])
                    append_data_to_file(data_rows, args, status_dict)

            else:
                append_data_to_file(data_rows, args, status_dict)

        print >> sys.stderr, "Battery %dmV" % (status_dict['Batt'])

    elif data[-8:] == 'head_eof':
        # Status header block only
        data = data[:-8]
        status_dict = parse_status_header(data)
        print >> sys.stderr, "Status:", status_dict

    elif expect_data:
        print >> sys.stderr, "Failed to communicate with Light Log."
        sys.exit(1)

if __name__ == '__main__':
    main()
