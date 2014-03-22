#rem
Copyright (c) 2013, 2014, Gary C. Martin <gary@lightlogproject.org>
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
#endrem

#no_data ; Make sure re-programming does not zap eprom memory
#picaxe 14m2

;#define DEBUG_SENSORS ; Debug output for sensor data
;#define DEBUG_BUTTON ; Debug output for button state
;#define DEBUG_WRITE ; Debug output for data written to eprom
;#define DEBUG_FIRST_BOOT

init:
    ; Save all the power we can
    disablebod
    disabletime
    disconnect
    gosub low_speed

    symbol FIRMWARE_VERSION = 18
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
    symbol REGISTER_DAY_PHASE_WORD = 49

    symbol REGISTER_MEMORY_WRAPPED_WORD = 51

    symbol BYTES_PER_RECORD = 6
    symbol EEPROM_TOTAL_BYTES = 65536
    symbol END_EEPROM_ADDRESS = EEPROM_TOTAL_BYTES - 1
    symbol BYTE_GAP_AT_END = EEPROM_TOTAL_BYTES % BYTES_PER_RECORD
    symbol GAP_PLUS_RECORD = BYTE_GAP_AT_END + BYTES_PER_RECORD
    symbol LAST_VALID_RECORD = END_EEPROM_ADDRESS - GAP_PLUS_RECORD
    symbol LAST_VALID_BYTE = END_EEPROM_ADDRESS - BYTE_GAP_AT_END

    symbol red = w0
    symbol green = w1
    symbol blue = w2
	symbol white = w3
    symbol red_avg = w4
    symbol green_avg = w5
    symbol blue_avg = w6
    symbol white_avg = w7
    symbol tmp = w8
    symbol tmp2 = w9

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
        gosub default_light_calibration
	endif

    ; Keep a count of device reboots
    read REGISTER_REBOOT_COUNT_WORD, word tmp
    tmp = tmp + 1
    write REGISTER_REBOOT_COUNT_WORD, word tmp

    gosub flash_led

    flag = FLAG_REBOOT

main:
    for sample_loop = 1 to SAMPLES_PER_AVERAGE
        gosub read_RGBW_sensors
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
    read REGISTER_2_5KLUX_WHITE_WORD, word tmp
    read REGISTER_5KLUX_WHITE_WORD, word tmp2
    if white_avg >= tmp and white_avg < tmp2 then
        tmp2 = tmp2 - tmp ; 5K - 2.5K calibration delta
        tmp2 = 500 / tmp2 ; scale factor for one sensor unit
        tmp = white_avg - tmp * tmp2 + 500; goal points between 500 and 1,000
        goto goal_update
    endif

    read REGISTER_10KLUX_WHITE_WORD, word tmp
    if white_avg >= tmp2 and white_avg < tmp then
        tmp = tmp - tmp2 ; 10K - 5K calibration delta
        tmp = 1000 / tmp ; scale factor for one sensor unit
        tmp = white_avg - tmp2 * tmp + 1000; goal points between 1,000 and 2,000
        goto goal_update
    endif

    if white_avg >= tmp then
        tmp = 2000 ; maximum 2,000 points per min
        goto goal_update
    endif

    goto skip_goal_update

    goal_update:
    read REGISTER_LIGHT_GOAL_WORD, word tmp2
    if tmp2 < 60000 then
        tmp2 = tmp2 + tmp
    else
        tmp2 = 60000
    endif
    write REGISTER_LIGHT_GOAL_WORD, word tmp2

    skip_goal_update:

    ; Keep track of day phase cycle
    read REGISTER_DAY_PHASE_WORD, word tmp
    tmp = tmp + 1
    if tmp > 1440 then
        ; Reset goal and counter cycle every 1440 min
        tmp = 0
        write REGISTER_LIGHT_GOAL_WORD, word tmp
    endif
    write REGISTER_DAY_PHASE_WORD, word tmp

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
    read REGISTER_LAST_SAVE_WORD, word tmp
    hi2cout tmp, (red_byte, green_byte)
	tmp = tmp + 2
    hi2cout tmp, (blue_byte, white_byte)
	tmp = tmp + 2
    hi2cout tmp, (extra_byte, flag)
	tmp = tmp + 2

    ; Debug sensor output
    #ifdef DEBUG_WRITE
        gosub high_speed
        sertxd("Write to ", #tmp, _
               ", R=", #red_byte, _
               ", G=", #green_byte, _
               ", B=", #blue_byte, _
               ", W=", #white_byte, _
               ", E=", #extra_byte, _
               ", F=", #flag, 13)
        gosub low_speed
    #endif

    flag = FLAG_OK ; Clear any flag states

    ; Increment and write current position to micro eprom (mem bytes = 65536)
	if tmp >= LAST_VALID_RECORD then
        tmp = 0
        write REGISTER_LAST_SAVE_WORD, word tmp

        ; Keep track of memory wrapps
        read REGISTER_MEMORY_WRAPPED_WORD, word tmp
        tmp = tmp + 1
        write REGISTER_MEMORY_WRAPPED_WORD, word tmp

    else
        write REGISTER_LAST_SAVE_WORD, word tmp
    endif

    goto main

low_power_delay:
    ; Save power and sleep
    nap 6 : nap 5 : nap 4 : nap 0 : nap 0 ; ~2sec
    return

read_RGBW_sensors:
    high SENSOR_POWER
    readadc10 SENSOR_RED, red
    readadc10 SENSOR_GREEN, green
    readadc10 SENSOR_BLUE, blue
    readadc10 SENSOR_WHITE, white
    low SENSOR_POWER
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
        gosub high_speed
        flag = flag | FLAG_BUTTON
        gosub check_serial_comms

        ; Allow program upload during a button press
        reconnect

        ; User feedback based on light goal
        gosub read_RGBW_sensors

        ; Prevent program upload (saves power)
        disconnect

        read REGISTER_LIGHT_GOAL_WORD, word tmp
        if tmp >= 60000 then
            ; Minimim recommended light goal reached
            gosub pulse_led
            gosub pulse_led
            gosub pulse_led
            gosub pulse_led

        elseif tmp >= 40000 then
            ; Two thirds of light goal reached
            gosub pulse_led
            gosub pulse_led
            gosub pulse_led

        elseif tmp >= 20000 then
            ; Third of light goal reached
            gosub pulse_led
            gosub pulse_led

        else
            ; Less than a third of light goal
            gosub pulse_led
        endif
        gosub low_speed
    endif

    return

flash_led:
    ; Simple on/off flash (used on reboot)
    high LED
    nap 0
    low LED
    nap 2 ; 72ms
    return

pulse_led:
    read REGISTER_2_5KLUX_WHITE_WORD, word tmp
    if white >= tmp then
        ; Light is bright enough to count towards goal
        goto fast_pulse_led
    endif
    gosub high_speed
    ; Fade up
	for tmp = 0 to 13000 step 1625
        high LED
        pauseus tmp
        low LED
        gosub pulse_led_delay
    next tmp
    ; Fade down
	for tmp = 0 to 13000 step 1625
        high LED
        gosub pulse_led_delay
        low LED
        pauseus tmp
    next tmp
    gosub low_speed
    return

fast_pulse_led:
    gosub high_speed
    ; Fade up
	for tmp = 0 to 13000 step 6500
        high LED
        pauseus tmp
        low LED
        gosub pulse_led_delay
    next tmp
    ; Fade down
	for tmp = 0 to 13000 step 6500
        high LED
        gosub pulse_led_delay
        low LED
        pauseus tmp
    next tmp
    gosub low_speed
    return

pulse_led_delay:
    tmp = 13000 - tmp
    pauseus tmp
    tmp = 13000 - tmp
    return

check_serial_comms:
    gosub high_speed
    sertxd("Hello?")
    serrxd [150, serial_checked], ser_in_byte

    select case ser_in_byte
        case "a"
        gosub header_block

        case "c"
        gosub dump_data

        case "d"
        gosub dump_all_eprom_data

        case "e"
        gosub reset_pointer

        case "f"
        gosub reset_reboot_counter

        case "h"
        gosub calibrate_2_5Klux

        case "i"
        gosub calibrate_5Klux

        case "j"
        gosub calibrate_10Klux

        case "k"
        gosub calibrate_20Klux

        case "l"
        gosub zero_light_goal

        case "m"
        gosub zero_day_phase

        case "n"
        gosub half_day_phase

        case "z"
        gosub first_boot_init
    endselect

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

header_block:
    read REGISTER_UNIQUE_HW_ID_WORD1, word tmp
    sertxd("ID:", #tmp)
    read REGISTER_UNIQUE_HW_ID_WORD2, word tmp
    sertxd(",", #tmp, ";")
	read REGISTER_HARDWARE_VERSION_BYTE, tmp
    sertxd("HW:", #tmp, ";")
    sertxd("FW:", #FIRMWARE_VERSION, ";")
    read REGISTER_REBOOT_COUNT_WORD, word tmp
    sertxd("Boots:", #tmp, ";")
    read REGISTER_LAST_SAVE_WORD, word tmp
    sertxd("Pointer:", #tmp, ";")
    read REGISTER_MEMORY_WRAPPED_WORD, word tmp
    sertxd("Wrap:", #tmp, ";")
	read REGISTER_LOG_START_TIME_WORD1, word tmp
    sertxd("Start:", #tmp)
	read REGISTER_LOG_START_TIME_WORD2, word tmp
    sertxd(",", #tmp, ";")
    read REGISTER_2_5KLUX_RED_WORD, word tmp
    sertxd("2.5KluxR:", #tmp, ";")
    read REGISTER_2_5KLUX_GREEN_WORD, word tmp
    sertxd("2.5KluxG:", #tmp, ";")
    read REGISTER_2_5KLUX_BLUE_WORD, word tmp
    sertxd("2.5KluxB:", #tmp, ";")
    read REGISTER_2_5KLUX_WHITE_WORD, word tmp
    sertxd("2.5KluxW:", #tmp, ";")
    read REGISTER_5KLUX_RED_WORD, word tmp
    sertxd("5KluxR:", #tmp, ";")
    read REGISTER_5KLUX_GREEN_WORD, word tmp
    sertxd("5KluxG:", #tmp, ";")
    read REGISTER_5KLUX_BLUE_WORD, word tmp
    sertxd("5KluxB:", #tmp, ";")
    read REGISTER_5KLUX_WHITE_WORD, word tmp
    sertxd("5KluxW:", #tmp, ";")
    read REGISTER_10KLUX_RED_WORD, word tmp
    sertxd("10KluxR:", #tmp, ";")
    read REGISTER_10KLUX_GREEN_WORD, word tmp
    sertxd("10KluxG:", #tmp, ";")
    read REGISTER_10KLUX_BLUE_WORD, word tmp
    sertxd("10KluxB:", #tmp, ";")
    read REGISTER_10KLUX_WHITE_WORD, word tmp
    sertxd("10KluxW:", #tmp, ";")
    read REGISTER_20KLUX_RED_WORD, word tmp
    sertxd("20KluxR:", #tmp, ";")
    read REGISTER_20KLUX_GREEN_WORD, word tmp
    sertxd("20KluxG:", #tmp, ";")
    read REGISTER_20KLUX_BLUE_WORD, word tmp
    sertxd("20KluxB:", #tmp, ";")
    read REGISTER_20KLUX_WHITE_WORD, word tmp
    sertxd("20KluxW:", #tmp, ";")
    read REGISTER_LIGHT_GOAL_WORD, word tmp
    sertxd("Goal:", #tmp, ";")
    read REGISTER_DAY_PHASE_WORD, word tmp
    sertxd("Phase:", #tmp, ";")
    calibadc10 tmp
    tmp = 52378 / tmp * 2
    sertxd("Batt:", #tmp, "0mV", ";")
    sertxd("RGBW:", #red, ",", #green, ",", #blue, ",", #white)
    sertxd("head_eof")
    return

dump_data:
    ; Output data oldest to newest
    gosub header_block
    read REGISTER_MEMORY_WRAPPED_WORD, word tmp
    if tmp > 0 then
        ; Dump end block of memory first if memory has wrapped one or more times
        gosub dump_from_index_to_end
    endif
    gosub dump_up_to_index
    sertxd("data_eof")
    return

dump_all_eprom_data:
    ; Debug output all eprom data in memory order
    gosub header_block
    gosub dump_up_to_index:
    gosub dump_from_index_to_end
    sertxd("data_eof")
    return

dump_up_to_index:
    read REGISTER_LAST_SAVE_WORD, word tmp
    if tmp != 0 then
	    tmp = tmp - BYTES_PER_RECORD - 1
    endif
    for tmp2 = 0 to tmp step 6
        ; ser_in_byte used instead of flag to preserve its value
        hi2cin tmp2, (red_byte, green_byte, blue_byte, white_byte, extra_byte, ser_in_byte)
        sertxd (red_byte, green_byte, blue_byte, white_byte, extra_byte, ser_in_byte)
    next tmp2
    return

dump_from_index_to_end:
    read REGISTER_LAST_SAVE_WORD, word tmp
    if tmp != 0 then
	    tmp = tmp - BYTES_PER_RECORD
    endif
    for tmp2 = tmp to LAST_VALID_BYTE step 6
        ; ser_in_byte used instead of flag to preserve its value
        hi2cin tmp2, (red_byte, green_byte, blue_byte, white_byte, extra_byte, ser_in_byte)
        sertxd (red_byte, green_byte, blue_byte, white_byte, extra_byte, ser_in_byte)
    next tmp2
    return

reset_pointer:
    tmp = 0 ; reset pointers back to start of mem
    write REGISTER_LAST_SAVE_WORD, word tmp
    write REGISTER_MEMORY_WRAPPED_WORD, word tmp
    return

reset_reboot_counter:
    tmp = 0
    write REGISTER_REBOOT_COUNT_WORD, word tmp ; reset reboot counter back to 0
    return

first_boot_init:
    gosub reset_pointer
    gosub reset_reboot_counter
    gosub zero_light_goal
    gosub zero_day_phase
    write REGISTER_HARDWARE_VERSION_BYTE, HARDWARE_VERSION
    tmp = 0
    write REGISTER_LOG_START_TIME_WORD1, word tmp
    write REGISTER_LOG_START_TIME_WORD2, word tmp

    ; Generate unique hardware id (seed from sensor and battery readings)
    gosub read_RGBW_sensors
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
        sertxd("Unique ID: ", #tmp)
        read REGISTER_UNIQUE_HW_ID_WORD2, word tmp
        sertxd(", ", #tmp, 13)
        gosub low_speed
    #endif
    return

zero_light_goal:
    tmp = 0
    write REGISTER_LIGHT_GOAL_WORD, word tmp
    return

zero_day_phase:
    tmp = 0
    write REGISTER_DAY_PHASE_WORD, word tmp
    return

half_day_phase:
    tmp = 720
    write REGISTER_DAY_PHASE_WORD, word tmp
    return

default_light_calibration:
    ; Default calibration using full spectrum white light measured with
    ; device inside case, behind RGB & clear light gels, and at room temp.
    tmp = 579
    write REGISTER_2_5KLUX_RED_WORD, word tmp
    tmp = 468
    write REGISTER_2_5KLUX_GREEN_WORD, word tmp
    tmp = 435
    write REGISTER_2_5KLUX_BLUE_WORD, word tmp
    tmp = 794
    write REGISTER_2_5KLUX_WHITE_WORD, word tmp
    tmp = 662
    write REGISTER_5KLUX_RED_WORD, word tmp
    tmp = 566
    write REGISTER_5KLUX_GREEN_WORD, word tmp
    tmp = 529
    write REGISTER_5KLUX_BLUE_WORD, word tmp
    tmp = 838
    write REGISTER_5KLUX_WHITE_WORD, word tmp
    tmp = 719
    write REGISTER_10KLUX_RED_WORD, word tmp
    tmp = 633
    write REGISTER_10KLUX_GREEN_WORD, word tmp
    tmp = 608
    write REGISTER_10KLUX_BLUE_WORD, word tmp
    tmp = 862
    write REGISTER_10KLUX_WHITE_WORD, word tmp
    tmp = 789
    write REGISTER_20KLUX_RED_WORD, word tmp
    tmp = 733
    write REGISTER_20KLUX_GREEN_WORD, word tmp
    tmp = 698
    write REGISTER_20KLUX_BLUE_WORD, word tmp
    tmp = 887
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
