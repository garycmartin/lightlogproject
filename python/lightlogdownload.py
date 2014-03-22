#!/usr/local/bin/python
# coding=UTF-8

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

"""Downloads and convert data from a Light Log <http://lightlogproject.org>.

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

STEP_SECONDS = 60 # default
LINE_UP = '\033[A'
VERSION = 'v0.1'
CALIBRATION_DATA =  {'0': 0, '1': 28, '10': 60, '50': 213, '100': 296, '200': 406, '300': 461, '500': 531, '1000': 633, '2500': 794, '5000': 838, '10000': 862, '20000': 887, '50000': 916, '116000': 930}

    
def get_args():
    """
    Parses and returns command line arguments.
    """
    parser = argparse.ArgumentParser(description='Download and convert data from Light Log device <http://lightlogproject.org>.')
    parser.add_argument("-p", "--port",
                       help="serial port device or com name")

    group_download = parser.add_mutually_exclusive_group()
    group_download.add_argument("-l", "--lux",
                                help="convert raw sensor data to lux",
                                action="store_true")
    group_download.add_argument("-o", "--output",
                                help="output file name (csv format)")
    group_download.add_argument("--csv-header",
                                help="outputs column header in first row")

    group_version = parser.add_mutually_exclusive_group()
    group_version.add_argument("-v", "--version",
                                help="show version number",
                                action="store_true")
                        
    group = parser.add_mutually_exclusive_group()
    group.add_argument("-s", "--status",
                       help="display device status data",
                       action="store_true")
    group.add_argument("--eeprom",
                       help="download all eeprom data",
                       action="store_true")
    group.add_argument("--reset",
                       help="reset memory pointer",
                       action="store_true")
    group.add_argument("--zero-reboot-count",
                       help="zero reboot counter",
                       action="store_true")
    group.add_argument("--calibrate",
                       help="calibrate to 2.5K lux light source",
                       choices=['lux2500', 'lux5000', 'lux10000', 'lux20000'])
    group.add_argument("-z", "--zero-goal",
                       help="zero light goal",
                       action="store_true")
    group.add_argument("--zero-day-phase",
                       help="zero day phase (peak sleep point)",
                       action="store_true")
    group.add_argument("--half-day-phase",
                       help="half day phase (peak sleep point + 12hrs)",
                       action="store_true")
    group.add_argument("--first-boot-init",
                       help="manually trigger first boot init",
                       action="store_true")
                       
    if parser.parse_args().version:
        print >> sys.stderr, "Version", VERSION
        sys.exit(0)

    return parser.parse_args()

def get_serial_ports():
    """
    Returns a generator for all available serial ports.
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

def parse_status_header(status):
    """
    Extracts data from status header, returning it as a dictionary.
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
    for i in ('Goal', 'FW', '20KluxG', '20KluxB', '10KluxB', '20KluxW',
              '20KluxR', '5KluxB', '5KluxG', '5KluxR', '5KluxW', 'Phase',
              '2.5KluxG','2.5KluxB','HW', '2.5KluxW','2.5KluxR', '10KluxG',
              'Boots', 'Wrap', '10KluxW', 'Pointer', '10KluxR'):
        status_dict[i] = int(status_dict[i])
    return status_dict

def convert_to_lux(red, green, blue, white, status_dict):
    """
    Use pre-fitted average lux test data function to convert to lux.
    
    Idealy this function should use the current devices calibration data
    status_dict['2.5KluxW'], status_dict['5KluxW'], status_dict['10KluxW']
    status_dict['20KluxW'], etc to convert sensor data to lux. Currently
    this function has been pre-fitted to average calibration data from
    multiple devices.    
        RGB values are scaled relative to the clear sensor lux value as an
    estimate for how much each section of the spectra may map into the
    total lux value (lux is a measurement of the total visible spectrum EMF).
    RGB values are not (yet) calibrated to a set of known colour sources.
    """

    if white > 0:
        white = linear_interpolation(white)
        #white = ramberg_osgood_fit(white)
        #white = inverse_harris(white)
        #white = exponential_fit(white)
    else:
        white = 0.0
        
    if red + green + blue > 0:
        red_value = int(round(white * (float(red) / (red + green + blue))))
        green_value = int(round(white * (float(green) / (red + green + blue))))
        blue_value = int(round(white * (float(blue) / (red + green + blue))))
        white = red_value + green_value + blue_value
        return red_value, green_value, blue_value, white
                                                                          
                                                                          
    else:
        return 0, 0, 0, int(round(white))

def linear_interpolation(x):
    """
    Linear interpolation between recorded data point values.
    """
    x = float(x)
    if x < CALIBRATION_DATA['1']:
        x = x / CALIBRATION_DATA['1']
        
    elif x >= CALIBRATION_DATA['1'] and x < CALIBRATION_DATA['10']:
        x = (x - CALIBRATION_DATA['1']) / (CALIBRATION_DATA['10'] - CALIBRATION_DATA['1']) * 9 + 1

    elif x >= CALIBRATION_DATA['10'] and x < CALIBRATION_DATA['50']:
        x = (x - CALIBRATION_DATA['10']) / (CALIBRATION_DATA['50'] - CALIBRATION_DATA['10']) * 40 + 10

    elif x >= CALIBRATION_DATA['50'] and x < CALIBRATION_DATA['100']:
        x = (x - CALIBRATION_DATA['50']) / (CALIBRATION_DATA['100'] - CALIBRATION_DATA['50']) * 50 + 50

    elif x >= CALIBRATION_DATA['100'] and x < CALIBRATION_DATA['200']:
        x = (x - CALIBRATION_DATA['100']) / (CALIBRATION_DATA['200'] - CALIBRATION_DATA['100']) * 100 + 100

    elif x >= CALIBRATION_DATA['200'] and x < CALIBRATION_DATA['300']:
        x = (x - CALIBRATION_DATA['200']) / (CALIBRATION_DATA['300'] - CALIBRATION_DATA['200']) * 100 + 200

    elif x >= CALIBRATION_DATA['300'] and x < CALIBRATION_DATA['500']:
        x = (x - CALIBRATION_DATA['300']) / (CALIBRATION_DATA['500'] - CALIBRATION_DATA['300']) * 200 + 300

    elif x >= CALIBRATION_DATA['500'] and x < CALIBRATION_DATA['1000']:
        x = (x - CALIBRATION_DATA['500']) / (CALIBRATION_DATA['1000'] - CALIBRATION_DATA['500']) * 500 + 500

    elif x >= CALIBRATION_DATA['1000'] and x < CALIBRATION_DATA['2500']:
        x = (x - CALIBRATION_DATA['1000']) / (CALIBRATION_DATA['2500'] - CALIBRATION_DATA['1000']) * 1500 + 1000

    elif x >= CALIBRATION_DATA['2500'] and x < CALIBRATION_DATA['5000']:
        x = (x - CALIBRATION_DATA['2500']) / (CALIBRATION_DATA['5000'] - CALIBRATION_DATA['2500']) * 2500 + 2500

    elif x >= CALIBRATION_DATA['5000'] and x < CALIBRATION_DATA['10000']:
        x = (x - CALIBRATION_DATA['5000']) / (CALIBRATION_DATA['10000'] - CALIBRATION_DATA['5000']) * 5000 + 5000

    elif x >= CALIBRATION_DATA['10000'] and x < CALIBRATION_DATA['20000']:
        x = (x - CALIBRATION_DATA['10000']) / (CALIBRATION_DATA['20000'] - CALIBRATION_DATA['10000']) * 10000 + 10000

    elif x >= CALIBRATION_DATA['20000'] and x < CALIBRATION_DATA['50000']:
        x = (x - CALIBRATION_DATA['20000']) / (CALIBRATION_DATA['50000'] - CALIBRATION_DATA['20000']) * 30000 + 20000

    elif x >= CALIBRATION_DATA['50000'] and x < CALIBRATION_DATA['116000']:
        x = (x - CALIBRATION_DATA['50000']) / (CALIBRATION_DATA['116000'] - CALIBRATION_DATA['50000']) * 66000 + 50000

    else:
        # Estimated (that sensor maxes out 1023 = 200Klux, no test data)
        x = (x - CALIBRATION_DATA['116000']) / (1023 - CALIBRATION_DATA['116000']) * 84000 + 116000
        
    return x

def inverse_harris(x):
    """
    http://zunzun.com/Equation/2/YieldDensity/InverseHarris/
    """
    x = float(x)
    a = -1.0418515764334417E+00
    b = 1.4647346407912545E+02
    c = -7.2246864466197369E-01
    return x / (a + b * x ** c)

def ramberg_osgood_fit(x):
    """
    http://zunzun.com/Equation/2/Engineering/Ramberg-Osgood/
    """
    x = float(x)
    youngs_modulus = 1.9765780295845900E-01
    k = 7.4474601294925719E+02
    n = 1.9137962029987306E-02
    return (x / youngs_modulus) + (x / k) ** (1.0 / n)

def exponential_fit(x):
    """
    http://zunzun.com/Equation/2/Exponential/Exponential/
    """
    x = float(x)
    a = 2.1242230658871749E-15
    b = 4.8842737652298622E-02
    return a * math.exp(b * x)

def main():
    args = get_args()
    data = ''

    if args.output:
        use_log_file = True
        output_log_file = args.output
    else:
        use_log_file = False

    if args.port:
        serial_ports = [args.port]
    else:
        serial_ports = list(get_serial_ports())[::-1]
    
    for port in serial_ports:
        try:
            # Open serial connection
            ser = serial.Serial(port, 38400, timeout=0)
            
        except (OSError, IOError):
            print >> sys.stderr, "No Light Log device found, tried %s." % (list(serial_ports))
            sys.exit(1)
            
        else:
            print >> sys.stderr, "Listening to %s for data (press Light Log button)" % (port)
            if use_log_file:
                # Open file for appending new serial data
                f = open(output_log_file, "a")
            break
    
    # Download available data
    wait_time = 10
    timer = time.time()
    message_update = 512
    communication_phase = 0

    while True:
        time.sleep(0.001) # free up some cpu
        if data[-8:] == 'data_eof':
            # Data downloaded
            break

        if time.time() - timer > wait_time:
            # Give up waiting
            break

        raw_data = ser.read(256)
        if len(raw_data) > 0:
            data += raw_data
            timer = time.time()
            wait_time = 1

            if data[-6:] == 'Hello?':
                data = ''
            
                if communication_phase == 0:
                    if args.status:
                        ser.write('a') # a = request status output
                    elif args.eeprom:
                        ser.write('d') # d = dump all eprom data
                    elif args.reset:
                        ser.write('e') # e = reset mem pointer!
                    elif args.zero_reboot_count:
                        ser.write('f') # f = reset reboot counter
                    elif args.calibrate == 'lux2500':
                        ser.write('h') # h = calibrate to 2.5K lux!!
                    elif args.calibrate == 'lux5000':
                        ser.write('i') # i = calibrate to 5K lux!!
                    elif args.calibrate == 'lux10000':
                        ser.write('j') # j = calibrate to 10K lux!!
                    elif args.calibrate == 'lux20000':
                        ser.write('k') # k = calibrate to 20K lux!!
                    elif args.zero_goal:
                        ser.write('l') # l = zero light goal
                    elif args.zero_day_phase:
                        ser.write('m') # m = zero day phase (peak sleep point)
                    elif args.half_day_phase:
                        ser.write('n') # n = half day phase (peak sleep point + half day)
                    elif args.first_boot_init:
                        ser.write('z') # z = first boot init (but not calibration zero)!!!
                    else:
                        ser.write('c') # c = download
                    communication_phase = 1
                    print >> sys.stderr, 'Communicating with Light Log'
                    # Grab current time now
                    seconds_now = int((datetime.datetime.now() - \
                                  datetime.datetime(1970,1,1,0,0)).total_seconds())

            if len(data) > message_update:
                message_update += 512
                print >> sys.stderr, 'Downloading data %d bytes%s' % (len(data), LINE_UP)

    ser.close()

    if len(data) > 512:
        print >> sys.stderr

    if data[-8:] == 'data_eof':
        # Strip off status head from data
        status, data = data.split('head_eof')
        status_dict = parse_status_header(status)
        print >> sys.stderr, "Status:", status_dict
        
        print >> sys.stderr, 'Processing Light Log data'
        data = data[:-8]
        seconds = seconds_now - (len(data) / 6 * STEP_SECONDS)
        count_samples = 0
        for i in range(0, len(data), 6):

            rgb = [ord(data[i]) + ((ord(data[i + 4]) & 0b11) * 256),
                   ord(data[i + 1]) + ((ord(data[i + 4]) & 0b1100) * 64),
                   ord(data[i + 2]) + ((ord(data[i + 4]) & 0b110000) * 16),
                   ord(data[i + 3]) + ((ord(data[i + 4]) & 0b11000000) * 4)]
                            
            flags = ord(data[i + 5]) >> 6
            # 11 = reboot
            # 01 = blocked sensors
            # 10 = button press
            # 00 = OK
            
            if args.lux:
                rgb[0], rgb[1], rgb[2], rgb[3] = convert_to_lux(rgb[0], rgb[1],
                                                                rgb[2], rgb[3],
                                                                status_dict)
                                        
            if use_log_file:
                f.write("%s,%s,%s,%s,%s,%s\n" % (rgb[0], rgb[1], rgb[2], rgb[3], seconds, flags))
            else:
                print "%s,%s,%s,%s,%s,%s" % (rgb[0], rgb[1], rgb[2], rgb[3], seconds, flags)
            seconds += STEP_SECONDS
            count_samples += 1

        data = ''
        print >> sys.stderr, "Downloaded", count_samples, "samples"

    elif data[-8:] == 'head_eof':
        # Status header block only
        data = data[:-8]
        status_dict = parse_status_header(data)
        print >> sys.stderr, "Status:", status_dict
        
    else:
        print >> sys.stderr, "No data block downloaded"
    
    if use_log_file:
        f.close()
    
if __name__ == '__main__':
    main()
