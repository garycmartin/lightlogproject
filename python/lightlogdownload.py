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

"""Download and convert data from a Lightlog <http://lightlogproject.org>.

Raw data bytes are downloaded from a Lightlog device through a serial port and
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
VERSION = 'v0.12'


def limit(value, low, high):
    if value > high or value < low:
        raise argparse.ArgumentTypeError("value should be in range %d-%d" %(low, high))
    return value


def phase_limit(string):
    value = int(string)
    limit(value, 0, 1440)
    return value


def delay_limit(string):
    value = int(string)
    limit(value, 500, 2000)
    return value


def sample_limit(string):
    value = int(string)
    limit(value, 1, 64)
    return value


def get_args():
    """\
    Parse and return command line arguments.
    """
    parser = argparse.ArgumentParser(description='Download, convert and save data from Lightlog device. Without arguments data will be saved to an auto-named csv file Light_Log_<device_ID>.csv in the current directory, if the log file already exists, new data will be appended to the log.')

    parser.add_argument("-p", "--port",
                        help="serial or COM port name")
    parser.add_argument("-r", "--raw",
                        help="raw 10-bit sensor data, no conversion to lux scale",
                        action="store_true")
    parser.add_argument("-b", "--both",
                        help="auto saves two files, raw 10-bit sensor data and one in lux",
                        action="store_true")
    parser.add_argument("--csv-header",
                        help="outputs column header in first row of data (new log files only)",
                        action="store_true")

    group = parser.add_mutually_exclusive_group()
    group.add_argument("-f", "--file",
                       help="save downloaded data to a named file")
    group.add_argument("--stdout",
                       help="send data to console sandard output",
                       action="store_true")
    group.add_argument("--cal",
                       help="calibrate hardware to current lux light exposure",
                       choices=['2.5k', '5k', '10k'])
    group.add_argument("--delay",
                       help="fine tune device delay timing between samples 500-2000 (default 1000 = 10sec)",
                       action="store",
                       type=delay_limit)
    group.add_argument("--phase",
                       help="set day phase 0-1439 in min (used for resetting daily goal)",
                       action="store",
                       type=phase_limit)
    group.add_argument("--sample",
                       help="number of samples per average 1-63 (default is 6 giving 1 record every minute)",
                       action="store",
                       type=sample_limit)
    group.add_argument("--status", "-s",
                       help="display device status data",
                       action="store_true")
    group.add_argument("--reset-memory",
                       help="reset memory pointer (for a fresh logging session)",
                       action="store_true")
    group.add_argument("--reset-cal",
                       help="reset lux calibration back to factory defaults",
                       action="store_true")
    group.add_argument("--reset-goal",
                       help="reset daily light goal",
                       action="store_true")
    group.add_argument("--factory-reset",
                       help="reset device back to all factory defaults, new unique hardware ID will be generated (!!!)",
                       action="store_true")
    group.add_argument("-v", "--version",
                       help="show download software version number and exit",
                       action="store_true")

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
    Extract data from Lightlog status header, returning a dictionary.
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
    for i in ('Goal', 'FW', '10KluxB', '5KluxB', '5KluxG', '5KluxR', '5KluxW', 'Delay',
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

    HW = status_dict['HW']
    r = float('%.4f' % linear_interpolation(red, HW))
    g = float('%.4f' % linear_interpolation(green, HW))
    b = float('%.4f' % linear_interpolation(blue, HW))
    w = float('%.4f' % linear_interpolation(white, HW))

    return r, g, b, w


def linear_interpolation(x, HW):
    """\
    Linear interpolation between recorded data point values from HW4 digital sensor devices.
    """
    if HW == 5:
        # SMT digital sensor in white case with larger sensor window
        calibration_data = [(0, 0), (1, 39), (8, 193), (50, 389), (100, 461), (250, 521), (500, 605), (1000, 673), (2500, 762), (5000, 819), (10000, 854), (15000, 880), (33000, 983), (60000, 1023)]

    elif HW == 4:
        # SMT digital sensor
        calibration_data = [(0, 0), (1, 29), (8, 175), (20, 258), (40, 321), (140, 446), (500, 572), (1000, 632), (1500, 658), (2000, 716), (2500, 0x322), (5000, 0x35F), (10000, 0x3A2), (20000, 945), (27000, 953), (85000, 0x3FF)]
    else:
        # LDR prototypes
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


def download_data_from_lightlog(ser, args):
    """\
    Download data from serial connection with Lightlog.
    """
    wait_time = 10
    timer = time.time()
    message_update = 2048
    communication_phase = 0
    data = ''
    seconds_now = None
    expect_data = True
    minute_since_midnight = None

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
                minute_since_midnight = get_minute_day_phase()
                minute_asci = bytes_from_int(minute_since_midnight)

                if communication_phase == 0:
                    if args.status:
                        ser.write('a' + minute_asci) # a = request status output
                        expect_data = True
                    elif args.reset_memory:
                        ser.write('e' + minute_asci) # e = reset mem pointer!
                    elif args.cal == '2.5k':
                        ser.write('h' + minute_asci) # h = calibrate to 2.5K lux source!!
                    elif args.cal == '5k':
                        ser.write('i' + minute_asci) # i = calibrate to 5K lux source!!
                    elif args.cal == '10k':
                        ser.write('j' + minute_asci) # j = calibrate to 10K lux source!!
                    elif args.reset_cal:
                        ser.write('k' + minute_asci) # k = rest to factory lux calibration
                    elif args.reset_goal:
                        ser.write('l' + minute_asci) # l = zero light goal
                    elif args.delay:
                        ser.write('d' + bytes_from_int(args.delay)) # d = set custom time delay
                    elif args.phase:
                        ser.write('p' + bytes_from_int(args.phase)) # p = set day phase
                    elif args.sample:
                        ser.write('s' + bytes_from_int(args.sample)) # s = set day phase
                    elif args.factory_reset:
                        ser.write('z' + minute_asci) # z = first boot init
                    else:
                        ser.write('c' + minute_asci) # c = download
                        expect_data = True
                    communication_phase = 1
                    sys.stdout.write('Communicating with Lightlog.')
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

    return data, seconds_now, minute_since_midnight, expect_data


def get_minute_day_phase():
    """\
    Return todays minutes (used to sync phase).
    """
    now = datetime.datetime.now()
    # TODO: Make this a 4am reset point by default
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    minute_since_midnight = int(round((now - midnight).total_seconds() / 60.0))
    return minute_since_midnight


def bytes_from_int(value):
    value_low_byte = value & 0xFF
    value_high_byte = value >>8 & 0xFF
    return chr(value_low_byte) + chr(value_high_byte)


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
        # 01 = blocked sensors (not currently used)
        # 10 = button press
        # 00 = OK

        if status_dict['FW'] >= 21:
            # Colour switched to 10-bit (0-1023) as percentage of white value
            r = int(round(w * (r / 1023.0)))
            g = int(round(w * (g / 1023.0)))
            b = int(round(w * (b / 1023.0)))

        # Raw sensor data
        if args.raw:
            # Raw sensor data
            data_rows.append([r, g, b, w, seconds, flags])
    
        else:
            r, g, b, w = convert_to_lux(r, g, b, w, status_dict)
            data_rows.append([r, g, b, w, seconds, flags])
            
        seconds += STEP_SECONDS

    try:
        f = open(args.file, "rb")
    except IOError:
        # File does not exist, just use extrapolated start time estimate
        return data_rows
    else:
        # See if we can use the last save data to calculate accurate timing
        last_log_end = get_timestamp_from_end_of_file(f)
        file_end_scent = get_scent_from_end_of_file(f)
        f.close()
 
        skip_rows = search_for_scent(data_rows, file_end_scent)
        if skip_rows != 0:
            # Interpolate new time stamps using skip_rows scent and last log end
            print >> sys.stderr, "Good join between previous and new data."
            data_rows = data_rows[skip_rows:]
            new_seconds = last_log_end
            new_step_seconds = (seconds_now - last_log_end) / float(len(data_rows))
            for i in range(len(data_rows)):
                data_rows[i][4] = int(new_seconds + (new_step_seconds * i))
        
        elif data_rows[0][4] < last_log_end:
            # Estimate using step seconds
            print >> sys.stderr, "Using step seconds to estimate time stamp."
            while data_rows[0][4] < last_log_end:
                data_rows.pop(0)

        else:
            # No scent found and step seconds estimate newer than last log end
            print >> sys.stderr, "WARNING: estimated %dmin gap between this and previous log data." % (int((data_rows[0][4] - last_log_end) / 60.0))
            
    return data_rows


def get_timestamp_from_end_of_file(f):
    f.seek(-2, 2)
    while f.read(1) != "\n":
        f.seek(-2, 1)
    return int(f.readline().split(',')[4])


def get_scent_from_end_of_file(f):
    """\
    Get last five RGBW data values from end of file.
    
    Could include the extra data value (especially if it gains more unique data).
    """
    f.seek(-2, 2)
    for i in range(4):
        seek_previous_new_line(f)
        f.seek(-2, 1)
    seek_previous_new_line(f)
    fifth = [string_to_number(i) for i in f.readline().split(',')[:-2]]
    forth = [string_to_number(i) for i in f.readline().split(',')[:-2]]
    third = [string_to_number(i) for i in f.readline().split(',')[:-2]]
    second = [string_to_number(i) for i in f.readline().split(',')[:-2]]
    last = [string_to_number(i) for i in f.readline().split(',')[:-2]]
    return [fifth, forth, third, second, last]


def seek_previous_new_line(f):
    """\
    Relative seek backwards until a new line is found.
    """
    while f.read(1) != "\n":
        f.seek(-2, 1)


def string_to_number(s):
    """\
    Return an int from a string if possible, or try a float.
    """
    try:
        return int(s)
    except ValueError:
        return float(s)


def search_for_scent(data_rows, file_end_scent):
    """\
    Search for scent from the end of the last file in the new data set.
    """
    skip_rows = 0
    
    # Check I have scent with some vaguly interesting data in it
    if file_end_scent[0] == file_end_scent[1] and \
        file_end_scent[1] == file_end_scent[2] and \
        file_end_scent[2] == file_end_scent[3] and \
        file_end_scent[3] == file_end_scent[4]:
        return skip_rows
            
    # TODO: toughen code to handle small log file case
    for search_row in range(len(data_rows)):
        if [i[0:4] for i in data_rows[search_row:search_row + 5]] == file_end_scent:
            skip_rows = search_row + 5
            if skip_rows >= len(data_rows):
                return 0
                
            #TODO: Search from new skip_rows and see if there is another (return 0 if so)
            
            return skip_rows
    
    return skip_rows


def store_data_to_file(data_rows, args, status_dict):
    """\
    Append data to the end of an existing log file, or create a new file if none exists.
    """
    try:
        f = open(args.file, "rb")
    except IOError:
        # File does not exist, creating a new file
        samples_stored = write_data_to_new_file(data_rows, args, status_dict)
    else:
        samples_stored = append_data_to_end_of_file(data_rows, args, status_dict)

    return samples_stored


def append_data_to_end_of_file(data_rows, args, status_dict):
    """\
    Append data to the end of an existing log file.
    """
    count_rows = 0
    f = open(args.file, "a")
    for row in data_rows:
        f.write("%s,%s,%s,%s,%s,%s\n" % (row[0], row[1], row[2], row[3], row[4], row[5]))
        count_rows += 1

    f.close()

    print >> sys.stderr, "Appended", count_rows,
    print >> sys.stderr, "samples to %s from Lightlog ID %s." % (args.file, status_dict['ID'])
    return count_rows


def write_data_to_new_file(data_rows, args, status_dict):
    """\
    Save data rows to file, will overwrite if file already exists.
    """
    f = open(args.file, "w")

    if args.csv_header:
        f.write("red,green,blue,white,epoch,flags\n")

    for row in data_rows:
        f.write("%s,%s,%s,%s,%s,%s\n" % (row[0], row[1], row[2], row[3], row[4], row[5]))
    f.close()

    print >> sys.stderr, "Wrote", len(data_rows),
    print >> sys.stderr, "samples to %s from Lightlog ID %s." % (args.file, status_dict['ID'])
    return len(data_rows)


def output_data_to_stdout(data_rows, args, status_dict):
    """\
    Output data rows to std out.
    """
    if args.csv_header:
        print "red,green,blue,white,epoch,flags"

    for row in data_rows:
        print "%s,%s,%s,%s,%s,%s" % (row[0], row[1], row[2], row[3], row[4], row[5])

    print >> sys.stderr, "Downloaded", len(data_rows),
    print >> sys.stderr, "samples from Lightlog ID %s." % (status_dict['ID'])


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
            print >> sys.stderr, "Trying %s (press Lightlog button)." % port
            data, seconds_now, minute_since_midnight, expect_data = download_data_from_lightlog(ser, args)
            ser.close()
            if len(data) > 0 or not expect_data:
                break

    if data[-8:] == 'data_eof':
        # Strip off status head from data
        status, data = data.split('head_eof')
        status_dict = parse_status_header(status)

        if args.stdout:
            data_rows = extract_data(data, args, seconds_now, status_dict)
            output_data_to_stdout(data_rows, args, status_dict)

        else:
            if not args.file:
                if args.both:
                    args.raw = True
                    args.file = 'Light_Log_%s_raw.csv' % (status_dict['ID'])
                    data_rows = extract_data(data, args, seconds_now, status_dict)
                    samples_stored = store_data_to_file(data_rows, args, status_dict)
                    args.raw = None
                    args.file = 'Light_Log_%s.csv' % (status_dict['ID'])
                    data_rows = extract_data(data, args, seconds_now, status_dict)
                    samples_stored = store_data_to_file(data_rows, args, status_dict)

                elif args.raw:
                    args.file = 'Light_Log_%s_raw.csv' % (status_dict['ID'])
                    data_rows = extract_data(data, args, seconds_now, status_dict)
                    samples_stored = store_data_to_file(data_rows, args, status_dict)

                else:
                    args.file = 'Light_Log_%s.csv' % (status_dict['ID'])
                    data_rows = extract_data(data, args, seconds_now, status_dict)
                    samples_stored = store_data_to_file(data_rows, args, status_dict)

            else:
                data_rows = extract_data(data, args, seconds_now, status_dict)
                samples_stored = store_data_to_file(data_rows, args, status_dict)
                
            print >> sys.stderr, 'Device day phase was %dmin, now set to %dmin' % (status_dict['Phase'], minute_since_midnight)
            if samples_stored > 0:
                if 'Delay' in status_dict:
                    device_delay = status_dict['Delay']
                else:
                    device_delay = 1000
                time_difference = minute_since_midnight - status_dict['Phase']
                # Correct only up to 12 hours drift & deal with midnight edge case
                if time_difference < -720:
                    time_difference += 1440
                elif time_difference > 720:
                    time_difference -= 1440
                ideal_delay = (samples_stored / float(time_difference + samples_stored)) * device_delay
                print >> sys.stderr, 'Device delay tuning is set to %d (%d suggested)' % (device_delay, int(round(ideal_delay)))

        print >> sys.stderr, "Battery %dmV" % (status_dict['Batt'])

    elif data[-8:] == 'head_eof':
        # Status header block only
        data = data[:-8]
        status_dict = parse_status_header(data)
        print >> sys.stderr, "Status:", status_dict

    elif expect_data:
        print >> sys.stderr, "Failed to communicate with Lightlog."
        sys.exit(1)

if __name__ == '__main__':
    main()
