#rem
Copyright (c) 2013, Gary C. Martin <gary@lightlogproject.org>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.


 14M2 ADC inputs for RGB light level logging to i2c 64K eprom
                                  _____
                             +V -|1 ^14|- 0V
               In/Serial In C.5 -|2  13|- B.0 Serial Out/Out/hserout/DAC
           Touch/ADC/Out/In C.4 -|3  12|- B.1 In/Out/ADC/Touch/SRI/hserin
                         In C.3 -|4  11|- B.2 In/Out/ADC/Touch/pwm/SRQ
     kbclk/hpwmA/pwm/Out/In C.2 -|5  10|- B.3 In/Out/ADC/Touch/hi2c scl
        kbdata/hpwmB/Out/In C.1 -|6   9|- B.4 In/Out/ADC/Touch/pwm/hi2c sda
 hpwmC/pwm/Touch/ADC/Out/In C.0 -|7   8|- B.5 In/Out/ADC/Touch/hpwmD
                                  –––––
                                  _____
                             +V -|1 ^14|- 0V
               In/Serial In C.5 -|2  13|- B.0 Serial Out/Out/hserout/DAC
             Sensors enable C.4 -|3  12|- B.1 Red ADC
                     Button C.3 -|4  11|- B.2 Green ADC
                            C.2 -|5  10|- B.3 hi2c scl
                        LED C.1 -|6   9|- B.4 hi2c sda
                  Clear ADC C.0 -|7   8|- B.5 Blue ADC
                                  –––––

TODO:
 - Software calibrate the sensor response curves as part of first init tests
 - Finishing adding code for clear LDR sensor
 - When full, compress data 50% and double number of samples per average and continue
 - Extend two way serial protocol:
   - log start time (and transmit it during sync)
   - generate device id for first boot (and transmit it during sync)
   - report hardware version in status (store in picaxe rom, defined during first run)
   - add a validate/checksum to sync process
 - Calculate and store average samples varience (indication of activity)?
 - HW: LED to C.2 would allow pwmout command for dimming control
 - HW: Use external RTC?
 - HW: Move B.1 for use of hardware serial in?
 - HW: Pull down all unused inputs to 0V, e.g. with 100K or even 1M resistors.
 - HW: Current-limit any outputs to the degree possible. (e.g. LEDs)
 - Use a button to interrupt, short press for marker, long hold for reboot
#endrem

#no_data ; <---- test this (re-programming should not zap eprom data)
#picaxe 14m2

;#define DEBUG_SENSORS ; Debug output for sensor data
;#define DEBUG_BUTTON ; Debug output for button state
;#define DEBUG_WRITE ; Debug output for data written to eprom
;#define DEBUG_FIRST_BOOT

init:
    ; Save all the power we can
    gosub low_speed
    disablebod
    disabletime
    disconnect

    symbol FIRMWARE_VERSION = 17
    symbol HARDWARE_VERSION = 3

    symbol LED = C.1
    symbol SENSOR_POWER = C.4
    symbol SENSOR_RED = B.1
    symbol SENSOR_GREEN = B.2
    symbol SENSOR_BLUE = B.5
    symbol SENSOR_WHITE = C.0
    symbol EVENT_BUTTON = pinC.3

    ; Button C.3 internal pullup resistor
    pullup %0000100000000000

    ; 63 = max (due to word int maths and avg overflow risk)
    symbol SAMPLES_PER_AVERAGE = 15

    symbol FLAG_OK = %00000000
    symbol FLAG_REBOOT = %11000000
    symbol FLAG_BLOCKED = %01000000
    symbol FLAG_BUTTON = %10000000

    symbol FIRST_BOOT_PASS_WORD = %1110010110100111

    symbol REGISTER_LAST_SAVE_WORD = 0
    symbol REGISTER_REBOOT_COUNT_WORD = 2
    symbol REGISTER_HARDWARE_VERSION_BYTE = 4
    symbol REGISTER_UNIQUE_HW_ID_WORD1 = 5
    symbol REGISTER_UNIQUE_HW_ID_WORD2 = 7
    symbol REGISTER_FIRST_BOOT_PASS_WORD = 9
    symbol REGISTER_LOG_START_TIME_WORD1 = 11
    symbol REGISTER_LOG_START_TIME_WORD2 = 13

    symbol REGISTER_2_5KLUX_RED_WORD = 15
    symbol REGISTER_2_5KLUX_GREEN_WORD = 17
    symbol REGISTER_2_5KLUX_BLUE_WORD = 19
    symbol REGISTER_2_5KLUX_WHITE_WORD = 21
    symbol REGISTER_5KLUX_RED_WORD = 23
    symbol REGISTER_5KLUX_GREEN_WORD = 25
    symbol REGISTER_5KLUX_BLUE_WORD = 27
    symbol REGISTER_5KLUX_WHITE_WORD = 29
    symbol REGISTER_10KLUX_RED_WORD = 31
    symbol REGISTER_10KLUX_GREEN_WORD = 33
    symbol REGISTER_10KLUX_BLUE_WORD = 35
    symbol REGISTER_10KLUX_WHITE_WORD = 37
    symbol REGISTER_20KLUX_RED_WORD = 39
    symbol REGISTER_20KLUX_GREEN_WORD = 41
    symbol REGISTER_20KLUX_BLUE_WORD = 43
    symbol REGISTER_20KLUX_WHITE_WORD = 45

    symbol REGISTER_LIGHT_GOAL_WORD = 47
    symbol REGISTER_LIGHT_COUNTER_WORD = 49

    symbol BYTES_PER_RECORD = 6
    symbol EEPROM_TOTAL_BYTES = 65536
    symbol END_EEPROM_ADDRESS = EEPROM_TOTAL_BYTES - 1
    symbol BYTE_GAP_AT_END = EEPROM_TOTAL_BYTES % BYTES_PER_RECORD
    symbol GAP_PLUS_RECORD = BYTE_GAP_AT_END + BYTES_PER_RECORD
    symbol LAST_VALID_RECORD = END_EEPROM_ADDRESS - GAP_PLUS_RECORD

    symbol red = w0
    symbol green = w1
    symbol blue = w2
	symbol white = w3
    symbol red_avg = w4
    symbol green_avg = w5
    symbol blue_avg = w6
    symbol white_avg = w7
    symbol index = w8
    symbol tmp = w9

    symbol red_byte = b20
    symbol green_byte = b21
    symbol blue_byte = b22
    symbol white_byte = b23
    symbol extra_byte = b24
    symbol ser_in_byte = b25
    symbol flag = b26
    symbol sample_loop = b27

    ; LED and sensors off
    low LED
    low SENSOR_POWER

	; First boot check
    read REGISTER_FIRST_BOOT_PASS_WORD, word tmp
    if tmp != FIRST_BOOT_PASS_WORD then
        gosub first_boot_init
        gosub zero_calibration; !!!
	endif

    ; Keep a count of device reboots
    read REGISTER_REBOOT_COUNT_WORD, word tmp
    tmp = tmp + 1
    write REGISTER_REBOOT_COUNT_WORD, word tmp

    gosub flash_led

    flag = FLAG_REBOOT

main:
    for sample_loop = 1 to SAMPLES_PER_AVERAGE
        high SENSOR_POWER ; Sensors on
        readadc10 SENSOR_RED, red
        readadc10 SENSOR_GREEN, green
        readadc10 SENSOR_BLUE, blue
        readadc10 SENSOR_WHITE, white
        low SENSOR_POWER ; Sensors off

        if sample_loop = 1 then
            ; Pre-fill averages for first pass
            red_avg = red
            green_avg = green
            blue_avg = blue
            white_avg = white
        else
            ; Accumulate average data samples
            red_avg = red + red_avg
            green_avg = green + green_avg
            blue_avg = blue + blue_avg
            white_avg = white + white_avg
        endif

        #ifdef DEBUG_SENSORS
            gosub high_speed
            sertxd("Sensors: R=", #red, _
                   ", G=", #green, _
                   ", B=", #blue, _
                   ", W=", #white, 13)
            gosub low_speed
        #endif

        gosub low_power_delay
        gosub check_user_button
        gosub low_power_delay
        gosub check_user_button
    next sample_loop

    ; Calculate averages
    red_avg = red_avg / SAMPLES_PER_AVERAGE
    green_avg = green_avg / SAMPLES_PER_AVERAGE
    blue_avg = blue_avg / SAMPLES_PER_AVERAGE
    white_avg = white_avg / SAMPLES_PER_AVERAGE

    ; Accumulate light for goal target
    ; TODO: Replace with smooth function between 2.5K and 10K
    read REGISTER_10KLUX_WHITE_WORD, word tmp
    if white_avg >= tmp then
        read REGISTER_LIGHT_GOAL_WORD, word tmp
        tmp = tmp + 100
        write REGISTER_LIGHT_GOAL_WORD, word tmp
        goto end_goal_update
    endif

    read REGISTER_5KLUX_WHITE_WORD, word tmp
    if white_avg >= tmp then
        read REGISTER_LIGHT_GOAL_WORD, word tmp
        tmp = tmp + 50
        write REGISTER_LIGHT_GOAL_WORD, word tmp
        goto end_goal_update
    endif

    read REGISTER_2_5KLUX_WHITE_WORD, word tmp
    if white_avg >= tmp then
        read REGISTER_LIGHT_GOAL_WORD, word tmp
        tmp = tmp + 25
        write REGISTER_LIGHT_GOAL_WORD, word tmp
        goto end_goal_update
    endif        

    end_goal_update:

    ; Keep (rough) track of daily cycle
    read REGISTER_LIGHT_COUNTER_WORD, word tmp
    tmp = tmp + 1
    if tmp > 1440 then
        ; Reset goal and counter cycle every 1440 min
        tmp = 0
        write REGISTER_LIGHT_GOAL_WORD, word tmp
    endif
    write REGISTER_LIGHT_COUNTER_WORD, word tmp

    ; Store least significant bytes
    red_byte = red_avg     & %11111111
    green_byte = green_avg & %11111111
    blue_byte = blue_avg   & %11111111
    white_byte = white_avg & %11111111

    ; Fill extra_byte with 9th and 10th bits of each RGBT
    extra_byte = red_avg   & %1100000000 / 256
    extra_byte = green_avg & %1100000000 / 64 + extra_byte
    extra_byte = blue_avg  & %1100000000 / 16 + extra_byte
    extra_byte = white_avg & %1100000000 / 4  + extra_byte

    ; Write data to eprom
    read REGISTER_LAST_SAVE_WORD, word index
    hi2cout index, (red_byte, green_byte)
	index = index + 2
    hi2cout index, (blue_byte, white_byte)
	index = index + 2
    hi2cout index, (extra_byte, flag)
	index = index + 2

    ; Debug sensor output
    #ifdef DEBUG_WRITE
        gosub high_speed
        sertxd("Write to ", #index, _
               ", R=", #red_byte, _
               ", G=", #green_byte, _
               ", B=", #blue_byte, _
               ", W=", #white_byte, _
               ", E=", #extra_byte, _
               ", F=", #flag, 13)
        gosub low_speed
    #endif

    flag = FLAG_OK ; Clear any flag states

    ; Increment and write position to micro eprom (mem bytes = 65536)
	if index >= LAST_VALID_RECORD then
        index = 0
    endif
    write REGISTER_LAST_SAVE_WORD, word index

    goto main

low_power_delay:
    ; Save power and sleep
    ;nap 8 ; ~4sec
    nap 6 : nap 5 : nap 4 : nap 0 : nap 0 ; ~2sec
    return

check_user_button:
    #ifdef DEBUG_BUTTON
        gosub high_speed
        if EVENT_BUTTON = 0 then
            sertxd("Button ON", 13)
        else
            sertxd("Button OFF", 13)
        endif
        gosub low_speed
    #endif

    if EVENT_BUTTON = 0 then
        flag = flag | FLAG_BUTTON
        gosub check_serial_comms
        reconnect
        read REGISTER_LIGHT_GOAL_WORD, word tmp
        if tmp > 3000 then
            gosub pulse_led
            gosub pulse_led
            gosub pulse_led
            gosub pulse_led
        elseif tmp > 2000 then
            gosub pulse_led
            gosub pulse_led
            gosub pulse_led
        elseif tmp > 1000 then
            gosub pulse_led
            gosub pulse_led
        else
            gosub pulse_led
        endif
        disconnect
    endif
    return

check_serial_comms:
    gosub high_speed
    sertxd("Hello?")
    serrxd [150, serial_checked], ser_in_byte

    if ser_in_byte = "a" then
        gosub display_status

    elseif ser_in_byte = "c" then
        gosub dump_data

    elseif ser_in_byte = "d" then
        gosub dump_all_eprom_data

    elseif ser_in_byte = "e" then
        gosub reset_pointer

    elseif ser_in_byte = "f" then
        gosub reset_reboot_counter

    elseif ser_in_byte = "g" then
        gosub erase_all_data

    elseif ser_in_byte = "h" then
        gosub calibrate_2_5Klux

    elseif ser_in_byte = "i" then
        gosub calibrate_5Klux

    elseif ser_in_byte = "j" then
        gosub calibrate_10Klux

    elseif ser_in_byte = "k" then
        gosub calibrate_20Klux

    elseif ser_in_byte = "z" then
        gosub first_boot_init

    else
        sertxd("Unknown command: ", ser_in_byte, 13)

    endif

    serial_checked:
    gosub low_speed
    return

calibrate_2_5Klux:
    write REGISTER_2_5KLUX_RED_WORD, word red
    write REGISTER_2_5KLUX_GREEN_WORD, word green
    write REGISTER_2_5KLUX_BLUE_WORD, word blue
    write REGISTER_2_5KLUX_WHITE_WORD, word white
    return

calibrate_5Klux:
    write REGISTER_5KLUX_RED_WORD, word red
    write REGISTER_5KLUX_GREEN_WORD, word green
    write REGISTER_5KLUX_BLUE_WORD, word blue
    write REGISTER_5KLUX_WHITE_WORD, word white
    return

calibrate_10Klux:
    write REGISTER_10KLUX_RED_WORD, word red
    write REGISTER_10KLUX_GREEN_WORD, word green
    write REGISTER_10KLUX_BLUE_WORD, word blue
    write REGISTER_10KLUX_WHITE_WORD, word white
    return

calibrate_20Klux:
    write REGISTER_20KLUX_RED_WORD, word red
    write REGISTER_20KLUX_GREEN_WORD, word green
    write REGISTER_20KLUX_BLUE_WORD, word blue
    write REGISTER_20KLUX_WHITE_WORD, word white
    return

flash_led:
    high LED
    nap 0
    low LED
    nap 2 ; 72ms
    return

pulse_led:
    gosub high_speed
    ; Fade up
	for tmp = 0 to 13000 step 1300
        high LED
        pauseus tmp
        low LED
        tmp = 15000 - tmp
        pauseus tmp
        tmp = 15000 - tmp
    next tmp
    ; Fade down
	for tmp = 0 to 13000 step 1300
        high LED
        tmp = 15000 - tmp
        pauseus tmp
        tmp = 15000 - tmp
        low LED
        pauseus tmp
    next tmp
    gosub low_speed
    return

display_status:
    read REGISTER_UNIQUE_HW_ID_WORD1, word tmp
    sertxd("Unique_ID:", #tmp)
    read REGISTER_UNIQUE_HW_ID_WORD2, word tmp
    sertxd(",", #tmp, 13)
	read REGISTER_HARDWARE_VERSION_BYTE, tmp
    sertxd("Hardware:", #tmp, 13)
    sertxd("Firmware:", #FIRMWARE_VERSION, 13)
    read REGISTER_REBOOT_COUNT_WORD, word tmp
    sertxd("RebootCount:", #tmp, 13)
    read REGISTER_LAST_SAVE_WORD, word index
    sertxd("MemoryPointer:", #index, 13)
	read REGISTER_LOG_START_TIME_WORD1, word tmp
    sertxd("TimeStart:", #tmp)
	read REGISTER_LOG_START_TIME_WORD2, word tmp
    sertxd(",", #tmp, 13)
    read REGISTER_2_5KLUX_RED_WORD, word tmp
    sertxd("2.5KluxRed:", #tmp, 13)
    read REGISTER_2_5KLUX_GREEN_WORD, word tmp
    sertxd("2.5KluxGreen:", #tmp, 13)
    read REGISTER_2_5KLUX_BLUE_WORD, word tmp
    sertxd("2.5KluxBlue:", #tmp, 13)
    read REGISTER_2_5KLUX_WHITE_WORD, word tmp
    sertxd("2.5KluxWhite:", #tmp, 13)
    read REGISTER_5KLUX_RED_WORD, word tmp
    sertxd("5KluxRed:", #tmp, 13)
    read REGISTER_5KLUX_GREEN_WORD, word tmp
    sertxd("5KluxGreen:", #tmp, 13)
    read REGISTER_5KLUX_BLUE_WORD, word tmp
    sertxd("5KluxBlue:", #tmp, 13)
    read REGISTER_5KLUX_WHITE_WORD, word tmp
    sertxd("5KluxWhite:", #tmp, 13)
    read REGISTER_10KLUX_RED_WORD, word tmp
    sertxd("10KluxRed:", #tmp, 13)
    read REGISTER_10KLUX_GREEN_WORD, word tmp
    sertxd("10KluxGreen:", #tmp, 13)
    read REGISTER_10KLUX_BLUE_WORD, word tmp
    sertxd("10KluxBlue:", #tmp, 13)
    read REGISTER_10KLUX_WHITE_WORD, word tmp
    sertxd("10KluxWhite:", #tmp, 13)
    read REGISTER_20KLUX_RED_WORD, word tmp
    sertxd("20KluxRed:", #tmp, 13)
    read REGISTER_20KLUX_GREEN_WORD, word tmp
    sertxd("20KluxGreen:", #tmp, 13)
    read REGISTER_20KLUX_BLUE_WORD, word tmp
    sertxd("20Klux Blue:", #tmp, 13)
    read REGISTER_20KLUX_WHITE_WORD, word tmp
    sertxd("20KluxWhite:", #tmp, 13)
    read REGISTER_LIGHT_GOAL_WORD, word tmp
    sertxd("LightGoal:", #tmp, 13)
    read REGISTER_LIGHT_COUNTER_WORD, word tmp
    sertxd("LightCounter:", #tmp, 13)
    calibadc10 tmp
    tmp = 52378 / tmp * 2
    sertxd("Batttey:", #tmp, "0mV", 13)
    sertxd("SensorsRGBW:", #red, ",", #green, ",", #blue, ",", #white, 13)
    return

dump_data:
    ; Debug output data
    read REGISTER_LAST_SAVE_WORD, word index
    if index != 0 then
	    index = index - BYTES_PER_RECORD
    endif
    for tmp = 0 to index
        hi2cin tmp, (red_byte)
        sertxd (red_byte)
    next tmp
    sertxd("eof")
    return

dump_all_eprom_data:
    ; Debug output all eprom data
    for tmp = 0 to LAST_VALID_RECORD step BYTES_PER_RECORD
        hi2cin tmp, (red_byte, green_byte, blue_byte, white_byte, extra_byte, flag)
        sertxd (red_byte, green_byte, blue_byte, white_byte, extra_byte, flag)
    next tmp
    sertxd("eof")
    return

reset_pointer:
    index = 0 ; reset pointer back to start of mem
    write REGISTER_LAST_SAVE_WORD, word index
    return

reset_reboot_counter:
    tmp = 0
    write REGISTER_REBOOT_COUNT_WORD, word tmp ; reset reboot counter back to 0
    return

erase_all_data:
    ; Debug erase eprom data (help with debugging)
    for tmp = 0 to 65518 step 16
        hi2cout tmp, (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        nap 0 ; Needs a delay or else looses writes
    next tmp
    gosub reset_pointer
    gosub reset_reboot_counter
    return

first_boot_init:
    write REGISTER_HARDWARE_VERSION_BYTE, HARDWARE_VERSION
    tmp = 0
    write REGISTER_REBOOT_COUNT_WORD, word tmp
    write REGISTER_LAST_SAVE_WORD, word tmp
    write REGISTER_LOG_START_TIME_WORD1, word tmp
    write REGISTER_LOG_START_TIME_WORD2, word tmp
    write REGISTER_LIGHT_GOAL_WORD, word tmp
    write REGISTER_LIGHT_COUNTER_WORD, word tmp

    ; Generate unique hardware id (seed from sensor and battery readings)
    high SENSOR_POWER
    readadc10 SENSOR_RED, red
    readadc10 SENSOR_GREEN, green
    readadc10 SENSOR_BLUE, blue
    readadc10 SENSOR_WHITE, white
    low SENSOR_POWER
    calibadc10 tmp
    tmp = red * green * blue * white * tmp
    random tmp
    write REGISTER_UNIQUE_HW_ID_WORD1, word tmp
    tmp = red * green * blue * white * tmp
    random tmp
    write REGISTER_UNIQUE_HW_ID_WORD2, word tmp

    ; Mark first boot as passed
    tmp = FIRST_BOOT_PASS_WORD
    write REGISTER_FIRST_BOOT_PASS_WORD, word tmp

    #ifdef DEBUG_FIRST_BOOT
        gosub high_speed
        sertxd("First boot", 13)
        read REGISTER_UNIQUE_HW_ID_WORD1, word tmp
        sertxd("Unique HW ID: ", #tmp)
        read REGISTER_UNIQUE_HW_ID_WORD2, word tmp
        sertxd(", ", #tmp, 13)
        gosub low_speed
    #endif
    return

zero_calibration:
    tmp = 0
    write REGISTER_2_5KLUX_RED_WORD, word tmp
    write REGISTER_2_5KLUX_GREEN_WORD, word tmp
    write REGISTER_2_5KLUX_BLUE_WORD, word tmp
    write REGISTER_2_5KLUX_WHITE_WORD, word tmp
    write REGISTER_5KLUX_RED_WORD, word tmp
    write REGISTER_5KLUX_GREEN_WORD, word tmp
    write REGISTER_5KLUX_BLUE_WORD, word tmp
    write REGISTER_5KLUX_WHITE_WORD, word tmp
    write REGISTER_10KLUX_RED_WORD, word tmp
    write REGISTER_10KLUX_GREEN_WORD, word tmp
    write REGISTER_10KLUX_BLUE_WORD, word tmp
    write REGISTER_10KLUX_WHITE_WORD, word tmp
    write REGISTER_20KLUX_RED_WORD, word tmp
    write REGISTER_20KLUX_GREEN_WORD, word tmp
    write REGISTER_20KLUX_BLUE_WORD, word tmp
    write REGISTER_20KLUX_WHITE_WORD, word tmp
    return

high_speed:
    setfreq m32; k31, k250, k500, m1, m2, m4, m8, m16, m32
    hi2csetup i2cmaster, %10100000, i2cfast_32, i2cword
    return

low_speed:
    setfreq k500; k31, k250, k500, m1, m2, m4, m8, m16, m32
    hi2csetup i2cmaster, %10100000, i2cfast, i2cword
    return
