Lightlog Project
===============

A wearable, Open Source, ambient colour light tracker.

Installing tools for data download
----------------------------------

To download data from Lightlog you'll need to set up your machine with some tools.

1) Install the device driver for the USB sync cable, install documentation steps, and driver are available here.

	http://www.picaxe.com/Software/Drivers/AXE027-USB-Cable-Driver/#download

2) For Mac and Linux systems Python is usually already installed. If your using Windows and don’t have Python installed, there's a nice quick guide here if you need it.

	http://www.anthonydebarros.com/2011/10/15/setting-up-python-in-windows-7/

3) For Windows, make sure Python is added to your PATH variable, this is covered in the above guide.

	C:\Python27;C:\Python27\Lib\site-packages\;C:\Python27\Scripts\;

4) Install pySerial module. The above guide also includes steps to add setuptools and pip, once you have them added you can type:

	pip install pyserial

5) Download the lightlogdownload.py script from:

    https://raw.githubusercontent.com/garycmartin/lightlogproject/master/python/lightlogdownload.py

…or make a local clone of the git repository. Github provides graphical git clients at https://desktop.github.com if needed.

	https://github.com/garycmartin/lightlogproject/blob/master/python/lightlogdownload.py

6) Test that you can run the script ok by trying to check its version:

	python lightlogdownload.py --version
	Version v0.13

7) Finally, plug in the serial cable, attach a Lightlog, and run the script...

The usual work flow is to run:

	python lightlogdownload.py

This will try to automatically find the connected serial port and communicate with Lightlog. Hold the button down on the Lightlog when it asks to establish the down link. The script will then download all logged data and save a .csv file of lux values containing red, green, blue, white, epoch seconds, and flags. The auto save file name includes the Light Log's unique ID, and if the save file already exists it will append any new data since the last download. This should make it easy to plug in each device, one after the other, and run the command each week to build up a continuous archive of data. Make sure you grab the data once a week (the default is one record a minute) or you'll have gaps in your data (at one record a minute, the memory holds 7days 14hrs worth of samples).

The epoch timestamps are seconds since 1st, Jan, 1970 (AKA Unix time, or POSIX time), you can quickly check a timestamp if needed with the below code snipped:

	python -c 'import datetime; print (datetime.datetime(1970,1,1) + datetime.timedelta(seconds=1395802371))'
	2014-03-26 02:52:51

For reference here's the download command's full arguments:

    $ python lightlogdownload.py --help
    usage: lightlogdownload.py [-h] [-p PORT] [-r] [-b] [--csv-header]
                           [--estimate]
                           [-f FILE | --stdout | --cal {2.5k,5k,10k} | --delay DELAY | --phase PHASE | --sample SAMPLE | --status | --reset-memory | --reset-cal | --reset-goal | --factory-reset | -v]
    
    Download, convert and save data from Lightlog device. Without arguments data will be saved to an auto-named csv file Light_Log_<device_ID>.csv in the current directory, if the log file already exists, new data will be appended to the log.

    optional arguments:
      -h, --help            show this help message and exit
      -p PORT, --port PORT  serial or COM port name
      -r, --raw             raw 10-bit sensor data, no conversion to lux scale
      -b, --both            auto saves two files, raw 10-bit sensor data and one
                        in lux
      --csv-header          outputs column header in first row of data (new log
                        files only)
      --estimate            force time estimate based on device period setting
                        rather than log time data
      -f FILE, --file FILE  save downloaded data to a named file
      --stdout              send data to console sandard output
      --cal {2.5k,5k,10k}   calibrate hardware to current lux light exposure
      --delay DELAY         fine tune device delay timing between samples 500-2000
                        (default 1000 = 10sec)
      --phase PHASE         set day phase 0-1439 in min (used for resetting daily
                        goal)
      --sample SAMPLE       number of samples per average 1-63 (default is 6
                        giving 1 record every minute)
      --status, -s          display device status data
      --reset-memory        reset memory pointer (for a fresh logging session)
      --reset-cal           reset lux calibration back to factory defaults
      --reset-goal          reset daily light goal
      --factory-reset       reset device back to all factory defaults, new unique
                        hardware ID will be generated (!!!)
      -v, --version         show download software version number and exit

Lightlogdownload.py script
--------------------------

When synching your devices I recommend using either the --raw or --both option, these generate a copy of the raw data before any calibration is applied (each device will generate a Light_Log_<device_ID>_raw.csv). If needed, this then allows you to control lux conversion/calibration using your own protocol, test equipment and math functions.

Without --raw or --both, you will only have the record of data after lux conversion has been applied using the code in Lightlogdownload.py. I have experimented with a number of fitted math curves to sample data sets, but none of them were satisfactory. My closest fit has been simply by interpolating between a set of lux vs. calibration data. The code is currently linearly interpolating between 16 calibration points.

Colour data
-----------

This python definition can be used if you want to convert the RGB values to colour temperature estimates:

    def calculate_colour_temp(colour):
       r = colour[0]
       g = colour[1]
       b = colour[2]
       n = ((0.23881 * r) + (0.25499 * g) + (-0.58291 * b)) / ((0.11109 * r) + (-0.85406 * g) + (0.52289 * b))
       cct = int(round(449 *  n ** 3 + 3525 *  n ** 2 + 6823.3 * n + 5520.33))
       return cct

Here’s another better commented example from Adafruit, where they use a library for the same sensor for Raspberry PI:

	https://github.com/adafruit/Adafruit-Raspberry-Pi-Python-Code/blob/master/Adafruit_TCS34725/Adafruit_TCS34725.py

    def calculate_colour_temp2(colour):
       r = colour[0]
       g = colour[1]
       b = colour[2]

       # 1. Map RGB values to their XYZ counterparts.
       # Based on 6500K fluorescent, 3000K fluorescent
       # and 60W incandescent values for a wide range.
       X = (-0.14282 * r) + (1.54924 * g) + (-0.95641 * b)
       Y = (-0.32466 * r) + (1.57837 * g) + (-0.73191 * b) # also lux?
       Z = (-0.68202 * r) + (0.77073 * g) + ( 0.56332 * b)
    
       #2. Calculate the chromaticity co-ordinates
       xc = (X) / (X + Y + Z)
       yc = (Y) / (X + Y + Z)
    
       #3. Use McCamy's formula to determine the CCT
       n = (xc - 0.3320) / (0.1858 - yc)
    
       #Calculate the final CCT
       cct = (449.0 * n**3) + (3525.0 * n**2) + (6823.3 * n) + 5520.33
       return cct

For the raw data R, G, B, W, Time, Flag; R, G, B are 10-bit (0-1023) % of W, and W is a 10-bit exponential stored value of the original sensor reading (based on potentially two different 16-bit sensor gain exposures, depending on light brightness, see below).

The cases where you see W > R+G+B will be down to the 10-bit resolution the data is stored to memory. The sensor device samples 16-bit data, and may take two exposures of light (if needed) at different gains, one at x16, if that over exposes it then takes a second sample at x1 gain. It then takes the 16-bit W value and uses it to create a delta value for each R, G, B from W. W is then converted to 10-bits of data using a logarithmic scale so there is high detail for indoor lighting environments, but outdoor cases are still covered. R, G, B are then each converted to 10-bit (0-1023) % values of the W value (e.g. if the red sensor was 50% of the white sensor, R=511), this provides maximum resolution for R, G, B for both high values of W and low values of W.
 
The FIFO log buffer, with the default delay of one RGBW+flag record per minute, will last 7.5 days before data starts being ovberwritten. For the most accurate of log file timing it is best that some of your data overlaps your previous log, if found, lightlogdownload.py will use this data overlap to adjust sample deltas using the accurate system clock. If the data does not overlap lightlogdownload.py uses the devices sample rate to set a fixed time between records (most recent records will be the most accurate, with oldest records having most drift).
 
There are 64Kbytes available on the EEPROM for logging, each record is 6 bytes, giving 10922 available records 

You'll occasionally see something like this from lightlogdownload.py:

    Device day phase was 225min, now set to 227min
    Device delay tuning is set to 982 (984 suggested)
 
The first item refers to the day phase (1440min each day, local midnight=0min). The second appears if there was a reasonable number of new samples, it tells you the current timing delay used by this device, and its suggestion. You can see here it suggesting the device slows down a little to correct for the time drift. If you agree you can run:

    $ python lightlogdownload.py --delay 984
 
It's not done automatically during a sync as it can't know how long you might have removed a battery for while replacing/changing. The delay value is already tuned at least a couple of times for the devices logging test data (over a couple of days duration minimum). Note that if your previous log file data overlaps with data in the device, lightlogdownload.py will adjust the sample timings between the start and end records using the real system time from your computer.

Battery life
------------

Expect to get 4 months (+/- a week) between battery changes under normal conditions.

If you want to have a safe margin of error, swap a battery once the script reports below 2.1V, you'll probably also notice the LEDs start to dim around this time as well.

The serial sync process and LED display are the most power hungry spikes that dip the voltage, so if the battery is low you may get a failed or no response message when trying to sync. Swapping out the battery for a new one, and trying to sync again should get all the data downloaded just fine. Be aware that very low temperatures will lower the battery voltage output.
