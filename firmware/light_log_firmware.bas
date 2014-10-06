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

14M2 connectedt via I2C to RGBC light sensor and logging to 64K EEPROM
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
               SENSOR_POWER C.4 -|3  12|- B.1 LED5
               EVENT_BUTTON C.3 -|4  11|- B.2 LED4
               EEPROM_POWER C.2 -|5  10|- B.3 hi2c scl
                       LED1 C.1 -|6   9|- B.4 hi2c sda
                       LED2 C.0 -|7   8|- B.5 LED3
                                  –––––

#endrem

; Lux calibration table (copied into data memory on first boot or factory reset)
; Each sample is measured from broard spectrum white SAD light source
; R_LOW, R_HIGH, G_LOW, G_HIGH, B_LOW, B_HIGH, C_LOW, C_HIGH @ 2.5k
; R_LOW, R_HIGH, G_LOW, G_HIGH, B_LOW, B_HIGH, C_LOW, C_HIGH @ 5k
; R_LOW, R_HIGH, G_LOW, G_HIGH, B_LOW, B_HIGH, C_LOW, C_HIGH @ 10k
table 15, (0x60, 0x02, 0x6E, 0x02, 0x60, 0x02, 0xD0, 0x02, _
           0x8E, 0x02, 0xAA, 0x02, 0x90, 0x02, 0x01, 0x03, _
           0xD6, 0x02, 0x2F, 0x02, 0xE0, 0x02, 0x4B, 0x03)

#no_data ; Make sure re-programming does not zap eeprom data memory
#picaxe 14m2

init:
    ; Save all the power we can
    disablebod ; disable 1.9V brownout detector
    disabletime ; Stop the time clock
    disconnect ; Don't listen for re-programming
    gosub normal_speed

    symbol FIRMWARE_VERSION = 20
    symbol HARDWARE_VERSION = 4 ; SMT v0.6 Rev A

    symbol EEPROM_POWER = C.2
    symbol SENSOR_POWER = C.4
    symbol LED1 = C.1
    symbol LED2 = C.0
    symbol LED3 = B.5
    symbol LED4 = B.2
    symbol LED5 = B.1
    symbol EVENT_BUTTON = pinC.3

    ; Button C.3 internal pullup resistor
    pullup %0000100000000000

    ; 63 = max (due to word int maths and avg overflow risk)
    symbol SAMPLES_PER_AVERAGE = 6
    symbol SECONDS_PER_RECORD = SAMPLES_PER_AVERAGE * 10

    symbol FLAG_OK = %00000000
    symbol FLAG_REBOOT = %11000000
    symbol FLAG_TBA = %01000000
    symbol FLAG_BUTTON = %10000000

    symbol FIRST_BOOT_PASS_WORD = %1110010110100111

    symbol REGISTER_LAST_SAVE_WORD = 0
    symbol REGISTER_REBOOT_COUNT_WORD = 2
    symbol REGISTER_HARDWARE_VERSION_BYTE = 4
    symbol REGISTER_UNIQUE_HW_ID_WORD1 = 5
    symbol REGISTER_UNIQUE_HW_ID_WORD2 = 7
    symbol REGISTER_FIRST_BOOT_PASS_WORD = 9

	; Populated by table at address 15 on first boot
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

    symbol REGISTER_LIGHT_GOAL_WORD = 47
    symbol REGISTER_DAY_PHASE_WORD = 49
    symbol REGISTER_MEMORY_WRAPPED_WORD = 51
    symbol REGISTER_BUTTON_LATCHED_WORD = 53

    symbol BYTES_PER_RECORD = 6
    symbol EEPROM_TOTAL_BYTES = 65536
    symbol END_EEPROM_ADDRESS = EEPROM_TOTAL_BYTES - 1
    symbol BYTE_GAP_AT_END = EEPROM_TOTAL_BYTES % BYTES_PER_RECORD
    symbol GAP_PLUS_RECORD = BYTE_GAP_AT_END + BYTES_PER_RECORD
    symbol LAST_VALID_RECORD = END_EEPROM_ADDRESS - GAP_PLUS_RECORD
    symbol LAST_VALID_BYTE = END_EEPROM_ADDRESS - BYTE_GAP_AT_END

	symbol TCS34725FN = %01010010
	symbol TCS34725FN_ID = %10110010
	symbol TCS34725FN_ATIME = %10100001
	symbol TCS34725FN_AGAIN = %10101111
	symbol TCS34725FN_ENABLE = %10100000
	symbol TCS34725FN_CDATA = %10110100
	symbol TCS34725FN_RDATA = %10110110
	symbol TCS34725FN_GDATA = %10111000
	symbol TCS34725FN_BDATA = %10111010
	symbol EEPROM_24LC512 = %10100000

    symbol red = w0
    symbol green = w1
    symbol blue = w2
    symbol white = w3
    symbol red_avg = w4
    symbol green_avg = w5
    symbol blue_avg = w6
    symbol white_avg = w7
    symbol tmp_word = w8
    symbol tmp_low_byte = b16
    symbol tmp_high_byte = b17
    symbol tmp2_word = w9
    symbol tmp2_low_byte = b18
    symbol tmp2_high_byte = b19
    symbol red_byte = b20
    symbol green_byte = b21
    symbol blue_byte = b22
    symbol white_byte = b23
    symbol extra_byte = b24
    symbol ser_in_byte = b25
    symbol flag = b26
    symbol sample_loop = b27

    ; First boot check
    read REGISTER_FIRST_BOOT_PASS_WORD, word tmp_word
    if tmp_word != FIRST_BOOT_PASS_WORD then
        gosub first_boot_init
    endif

    ; Keep a count of device reboots
    read REGISTER_REBOOT_COUNT_WORD, word tmp_word
    tmp_word = tmp_word + 1
    write REGISTER_REBOOT_COUNT_WORD, word tmp_word

	gosub default_light_calibration ; Only do this if button held down at boot?
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

        gosub delay_2sec
        gosub check_user_button
        gosub delay_2sec
        gosub check_user_button
        gosub delay_2sec
        gosub check_user_button
        gosub delay_2sec
        gosub check_user_button
        gosub delay_2sec
        gosub check_user_button
    next sample_loop

    ; Calculate averages
    red_avg = red_avg / SAMPLES_PER_AVERAGE
    green_avg = green_avg / SAMPLES_PER_AVERAGE
    blue_avg = blue_avg / SAMPLES_PER_AVERAGE
    white_avg = white_avg / SAMPLES_PER_AVERAGE

    ; Accumulate light for goal target
    read REGISTER_2_5KLUX_WHITE_WORD, word tmp_word
    read REGISTER_5KLUX_WHITE_WORD, word tmp2_word
    if white_avg >= tmp_word and white_avg < tmp2_word then
        tmp2_word = tmp2_word - tmp_word ; 5K - 2.5K calibration delta
        tmp2_word = 500 / tmp2_word ; scale factor for one sensor unit
        tmp_word = white_avg - tmp_word * tmp2_word + 500; goal points between 500 and 1,000
        goto goal_update
    endif

    read REGISTER_10KLUX_WHITE_WORD, word tmp_word
    if white_avg >= tmp2_word and white_avg < tmp_word then
        tmp_word = tmp_word - tmp2_word ; 10K - 5K calibration delta
        tmp_word = 1000 / tmp_word ; scale factor for one sensor unit
        tmp_word = white_avg - tmp2_word * tmp_word + 1000; goal points between 1,000 and 2,000
        goto goal_update
    endif

	; Check for brighter than 10K lux max score
    if white_avg >= tmp_word then
        tmp_word = 2000 ; maximum 2,000 points per min
	else
        goto end_goal_update
    endif

	goal_update:
		; Update the goal units reached so far into memory
    	read REGISTER_LIGHT_GOAL_WORD, word tmp2_word
    	tmp2_word = tmp2_word + tmp_word
    	if tmp2_word > 60000 then
    	    tmp2_word = 60000
    	endif
    	write REGISTER_LIGHT_GOAL_WORD, word tmp2_word

	end_goal_update:

    ; Keep track of day phase cycle
    read REGISTER_DAY_PHASE_WORD, word tmp_word
    tmp_word = tmp_word + 1
    if tmp_word > 1440 then
        ; Reset goal and counter cycle every 1440 min
        write REGISTER_LIGHT_GOAL_WORD, 0, 0
        tmp_word = 0
    endif
    write REGISTER_DAY_PHASE_WORD, word tmp_word

    ; Prepair to write data to eprom
    read REGISTER_LAST_SAVE_WORD, word tmp_word

    ; Store least significant bytes
    red_byte = red_avg     & %11111111
    hi2cout tmp_word, (red_byte)
    tmp_word = tmp_word + 1

    green_byte = green_avg & %11111111
    hi2cout tmp_word, (green_byte)
    tmp_word = tmp_word + 1

    blue_byte = blue_avg   & %11111111
    hi2cout tmp_word, (blue_byte)
    tmp_word = tmp_word + 1

    white_byte = white_avg & %11111111
    hi2cout tmp_word, (white_byte)
    tmp_word = tmp_word + 1

    ; Fill extra_byte with 9th and 10th bits of each RGBT
    extra_byte = red_avg   & %1100000000 / 256
    extra_byte = green_avg & %1100000000 / 64 + extra_byte
    extra_byte = blue_avg  & %1100000000 / 16 + extra_byte
    extra_byte = white_avg & %1100000000 / 4  + extra_byte

    hi2cout tmp_word, (extra_byte)
    tmp_word = tmp_word + 1

    hi2cout tmp_word, (flag)
    tmp_word = tmp_word + 1

    flag = FLAG_OK ; Clear any flag states

    ; Increment and write current position to micro eprom
    if tmp_word >= LAST_VALID_RECORD then
        write REGISTER_LAST_SAVE_WORD, 0, 0

        ; Keep track of memory wrapps
        read REGISTER_MEMORY_WRAPPED_WORD, word tmp_word
        tmp_word = tmp_word + 1
        write REGISTER_MEMORY_WRAPPED_WORD, word tmp_word

    else
        write REGISTER_LAST_SAVE_WORD, word tmp_word
    endif

    goto main

delay_2sec:
    ; Delay for 2 sec without using the low power sleep watchdog timer 
    ; More accurate, avoids intermittent crashes, but uses more power
    low EEPROM_POWER
    gosub low_speed
    pauseus 1227 ; use mean value for testing
    ;pauseus 1389 ; my daily worn test unit
    ;pauseus 1380 ; white case with green sensor error
    ;pauseus 1344 ; red case in livingroom window
    ;pauseus 1318 ; red case on lamp in livingroom
    ;pauseus 1286 ; blue case fridge
    ;pauseus 1484 ; blue case bedroom window
    gosub normal_speed
    high EEPROM_POWER
    return

read_RGBW_sensors:
    ; Enable TCS34725FN light sensor
    high SENSOR_POWER

    ; TCS34725FN I2C address 0x29, %00101001, use 7bitaddress + r/w bit...
    hi2csetup i2cmaster, TCS34725FN, i2cfast, i2cbyte

    ; ATIME - Set integration time
    ; 0xFF = 2.4ms - 1 cycle (1024 counts == 10 bits) <-- take advantage, quicker, less processing? 
    ; 0xFE = 4.8ms - 2 cycle (2048 counts == 11 bits)
    ; 0xFC = 9.6ms - 4 cycle (4096 counts == 12 bits)
    ; 0xF8 = 19.2ms - 8 cycle (8192 counts == 13 bits)
    ; 0xF0 = 38.4ms - 16 cycle (16384 counts == 14 bits)
    ; 0xDF = 77ms  - 32 cycles (33792 counts == 15 bits)
    ; 0xC0 = 154ms - 64 cycles (65535 counts == 16 bits)
    ; 0x80 = 308ms - 128 cycles (65535 counts)
    ; 0x00 = 700ms - 256 cycles (65535 counts)
    hi2cout TCS34725FN_ATIME, (0xC0)
    pause 3

    ; AGAIN - set gain for sensor
    ; 0x00=none
    ; 0x01=4x
    ; 0x02=16x
    ; 0x03=60x
    hi2cout TCS34725FN_AGAIN, (0x02)

	tmp2_low_byte = 0 ; Flag to indicate overexposed sample
	too_bright_retry_entry_point:

    pause 3

	; ENABLE - PON power on internal oscillator
	hi2cout TCS34725FN_ENABLE, (%00000001)
	pause 4; Min of 2.4ms before enabling RGBC

	; ENABLE - AEN, start RGBC ADC (and leave power ON)
	hi2cout TCS34725FN_ENABLE, (%00000011)

	; Wait ~intergration time before reading (should only need ~77ms for default, or so...)
	; TODO: Move/refactor this delay to an existing natural delay (e.g. button waits?)
	; <<<------ FIXME: currently messing up my log timing and stability no doubt...
	pause 44

	; Sleep once integration cycle completes
	hi2cout TCS34725FN_ENABLE, (%00000001)

	hi2cin TCS34725FN_CDATA, (tmp_low_byte, tmp_high_byte)

	; Check if overexposed
	if tmp_word = 0xFFFF and tmp2_low_byte = 0 then
	    ;sertxd(">", #tmp_word, ", ")
		tmp2_low_byte = 1
	    hi2cout TCS34725FN_AGAIN, (0x00)
		goto too_bright_retry_entry_point
	else
		; correct timing if first sample was good
	    ;sertxd("=", #tmp_word, ", ")
		pause 51
	endif

	gosub bit_compress
    white = tmp_word

	hi2cin TCS34725FN_RDATA, (tmp_low_byte, tmp_high_byte)
	gosub bit_compress
    red = tmp_word

	hi2cin TCS34725FN_GDATA, (tmp_low_byte, tmp_high_byte) 
	gosub bit_compress
    green = tmp_word

	hi2cin TCS34725FN_BDATA, (tmp_low_byte, tmp_high_byte)
	gosub bit_compress
    blue = tmp_word

    ; Power off TCS34725FN light sensor
    low SENSOR_POWER

    ;sertxd("W", #white, ", R", #red, ", G", #green, ", B", #blue, 13)
    return

bit_compress:
	; Check flag for x16 vs x1 exposure gain
	if tmp2_low_byte = 1 then
		gosub bit_compress_1x
	else
		gosub bit_compress_16x
	endif
	tmp_word = tmp_word / 16 + tmp_word ; scale to 0-1023 (1018) 10bit range per chanel
	return

bit_compress_16x:
	; Converts tmp_word to 10bit value (lossy 6bit significant, 4bit magnitude)
    if tmp_word < 128 then
		return
	elseif tmp_word < 256 then
        tmp_word = tmp_word / 2 + 64
    elseif tmp_word < 512 then
        tmp_word = tmp_word / 4 + 128
    elseif tmp_word < 1024 then
        tmp_word = tmp_word / 8 + 192
    elseif tmp_word < 2048 then
        tmp_word = tmp_word / 16 + 256
    elseif tmp_word < 4096 then
        tmp_word = tmp_word / 32 + 320
    elseif tmp_word < 8192 then
        tmp_word = tmp_word / 64 + 384
    elseif tmp_word < 16384 then
        tmp_word = tmp_word / 128 + 448
    elseif tmp_word < 32768 then
        tmp_word = tmp_word / 256 + 512
    else
        tmp_word = tmp_word / 512 + 576
    endif
    return

bit_compress_1x:
	; Converts tmp_word to 10bit value (lossy 6bit significant, 4bit magnitude)
    if tmp_word < 64 then
        tmp_word = tmp_word * 4 ; special case?
    elseif tmp_word < 128 then
        tmp_word = tmp_word * 2 + 128 ; special case?
    elseif tmp_word < 256 then
        tmp_word = tmp_word / 2 + 320
    elseif tmp_word < 512 then
        tmp_word = tmp_word / 4 + 384
    elseif tmp_word < 1024 then
        tmp_word = tmp_word / 8 + 448
    elseif tmp_word < 2048 then
        tmp_word = tmp_word / 16 + 512
    elseif tmp_word < 4096 then
        tmp_word = tmp_word / 32 + 576
    elseif tmp_word < 8192 then
        tmp_word = tmp_word / 64 + 640
    elseif tmp_word < 16384 then
        tmp_word = tmp_word / 128 + 704
    elseif tmp_word < 32768 then
        tmp_word = tmp_word / 256 + 768
    else
        tmp_word = tmp_word / 512 + 832
    endif
	return

check_user_button:
    if EVENT_BUTTON = 0 then
		; Check for button latch
        read REGISTER_BUTTON_LATCHED_WORD, word tmp_word
        if tmp_word > 3 then
            return
        endif
        tmp_word = tmp_word + 1
        write REGISTER_BUTTON_LATCHED_WORD, word tmp_word
        flag = flag | FLAG_BUTTON
        gosub check_serial_comms

        ; Allow program upload during a button press
        reconnect

        ; User feedback based on light goal
        gosub read_RGBW_sensors

        ; Prevent program upload (saves power)
        disconnect

		; Lead into bargraph
		gosub flash_led

		; Check if illumination is currently bright enough to count
		read REGISTER_2_5KLUX_WHITE_WORD, word tmp_word
		if white >= tmp_word then
			tmp2_high_byte = 16
		else
			tmp2_high_byte = 48
		endif

		; Display bar graph for daily goal progress
        read REGISTER_LIGHT_GOAL_WORD, word tmp_word
        for tmp2_low_byte = 0 to 6
        	high LED5
        	if tmp_word >= 12000 then
				high LED4
			endif
        	if tmp_word >= 24000 then
				high LED3
			endif
        	if tmp_word >= 36000 then
				high LED2
			endif
        	if tmp_word >= 48000 then
				high LED1
			endif
			pause tmp2_high_byte

   	     if tmp_word < 12000 then
				low LED5
			endif
    	    if tmp_word < 24000 then
				low LED4
			endif
    	    if tmp_word < 36000 then
				low LED3
			endif
    	    if tmp_word < 48000 then
				low LED2
			endif
    	    if tmp_word < 60000 then
				low LED1
			endif
        	pause tmp2_high_byte

        next tmp2_low_byte
		low LED1, LED2, LED3, LED4, LED5

    else
        write REGISTER_BUTTON_LATCHED_WORD, 0, 0
    endif

    return

flash_led:
    ; Simple LED sequence flash
	high LED5
	pause 8
	low LED5
	high LED4
	pause 8
	low LED4
	high LED3
	pause 8
	low LED3
	high LED2
	pause 8
	low LED2
	high LED1
	pause 8
	low LED1
    return

check_serial_comms:
    gosub comms_speed
    sertxd("Hello?")
    serrxd [150, serial_checked], ser_in_byte, tmp_low_byte, tmp_high_byte

    select case ser_in_byte
        case "a"
        gosub header_block

        case "c"
        gosub dump_data

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

        case "l"
        gosub zero_light_goal

        case "z"
        gosub first_boot_init
    endselect

    serial_checked:
    gosub normal_speed
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

header_block:
    read REGISTER_UNIQUE_HW_ID_WORD1, word tmp2_word
    sertxd("ID:", #tmp2_word)
    read REGISTER_UNIQUE_HW_ID_WORD2, word tmp2_word
    sertxd(",", #tmp2_word, ";")
    read REGISTER_HARDWARE_VERSION_BYTE, tmp2_word
    sertxd("HW:", #tmp2_word, ";")
    sertxd("FW:", #FIRMWARE_VERSION, ";")
    read REGISTER_REBOOT_COUNT_WORD, word tmp2_word
    sertxd("Boots:", #tmp2_word, ";")
    read REGISTER_LAST_SAVE_WORD, word tmp2_word
    sertxd("Pointer:", #tmp2_word, ";")
    read REGISTER_MEMORY_WRAPPED_WORD, word tmp2_word
    sertxd("Wrap:", #tmp2_word, ";")
    sertxd("Period:", #SECONDS_PER_RECORD, ";")
    read REGISTER_2_5KLUX_RED_WORD, word tmp2_word
    sertxd("2.5KluxR:", #tmp2_word, ";")
    read REGISTER_2_5KLUX_GREEN_WORD, word tmp2_word
    sertxd("2.5KluxG:", #tmp2_word, ";")
    read REGISTER_2_5KLUX_BLUE_WORD, word tmp2_word
    sertxd("2.5KluxB:", #tmp2_word, ";")
    read REGISTER_2_5KLUX_WHITE_WORD, word tmp2_word
    sertxd("2.5KluxW:", #tmp2_word, ";")
    read REGISTER_5KLUX_RED_WORD, word tmp2_word
    sertxd("5KluxR:", #tmp2_word, ";")
    read REGISTER_5KLUX_GREEN_WORD, word tmp2_word
    sertxd("5KluxG:", #tmp2_word, ";")
    read REGISTER_5KLUX_BLUE_WORD, word tmp2_word
    sertxd("5KluxB:", #tmp2_word, ";")
    read REGISTER_5KLUX_WHITE_WORD, word tmp2_word
    sertxd("5KluxW:", #tmp2_word, ";")
    read REGISTER_10KLUX_RED_WORD, word tmp2_word
    sertxd("10KluxR:", #tmp2_word, ";")
    read REGISTER_10KLUX_GREEN_WORD, word tmp2_word
    sertxd("10KluxG:", #tmp2_word, ";")
    read REGISTER_10KLUX_BLUE_WORD, word tmp2_word
    sertxd("10KluxB:", #tmp2_word, ";")
    read REGISTER_10KLUX_WHITE_WORD, word tmp2_word
    sertxd("10KluxW:", #tmp2_word, ";")
    read REGISTER_LIGHT_GOAL_WORD, word tmp2_word
    sertxd("Goal:", #tmp2_word, ";")
    read REGISTER_DAY_PHASE_WORD, word tmp2_word
    sertxd("Phase:", #tmp2_word, ";")
    calibadc10 tmp2_word
    tmp2_word = 52378 / tmp2_word * 2
    sertxd("Batt:", #tmp2_word, "0mV", ";")
    sertxd("RGBW:", #red, ",", #green, ",", #blue, ",", #white)
    sertxd("head_eof")
    return

update_time_and_phase:
	; Update day phase (crude test to check the value is at least sane)
    if tmp_word > 1440 then
		; Do nothing, must be bad value
		return
	endif
    read REGISTER_DAY_PHASE_WORD, word tmp2_word
	; Try and estimate if daily accumulated goal should be reset
	if tmp2_word > 1080 and tmp_word < 360 then
	    write REGISTER_LIGHT_GOAL_WORD, 0, 0
	endif
    write REGISTER_DAY_PHASE_WORD, word tmp_word
	return

dump_data:
    ; Output data oldest to newest
    gosub header_block
	gosub update_time_and_phase ; serial comms word passed via tmp_word
    read REGISTER_MEMORY_WRAPPED_WORD, word tmp_word
    if tmp_word > 0 then
        ; Dump end block of memory first if memory has wrapped one or more times
        gosub dump_from_index_to_end
    endif
    gosub dump_up_to_index
    sertxd("data_eof")
    return

dump_up_to_index:
    read REGISTER_LAST_SAVE_WORD, word tmp_word
    if tmp_word != 0 then
        tmp_word = tmp_word - BYTES_PER_RECORD - 1
    endif
    for tmp2_word = 0 to tmp_word step 6
        ; ser_in_byte used instead of flag to preserve its value
        hi2cin tmp2_word, (red_byte, green_byte, blue_byte, white_byte, extra_byte, ser_in_byte)
        sertxd (red_byte, green_byte, blue_byte, white_byte, extra_byte, ser_in_byte)
    next tmp2_word
    return

dump_from_index_to_end:
    read REGISTER_LAST_SAVE_WORD, word tmp_word
    if tmp_word != 0 then
        tmp_word = tmp_word - BYTES_PER_RECORD
    endif
    for tmp2_word = tmp_word to LAST_VALID_BYTE step 6
        ; ser_in_byte used instead of flag to preserve its value
        hi2cin tmp2_word, (red_byte, green_byte, blue_byte, white_byte, extra_byte, ser_in_byte)
        sertxd (red_byte, green_byte, blue_byte, white_byte, extra_byte, ser_in_byte)
    next tmp2_word
    return

reset_pointer:
    ; Reset pointers back to start of mem
    write REGISTER_LAST_SAVE_WORD, 0, 0
    write REGISTER_MEMORY_WRAPPED_WORD, 0, 0
    return

reset_reboot_counter:
    ; Reset reboot counter back to 0
    write REGISTER_REBOOT_COUNT_WORD, 0, 0 
    return

first_boot_init:
    gosub default_light_calibration
    gosub reset_pointer
    gosub reset_reboot_counter
    gosub zero_light_goal
    write REGISTER_DAY_PHASE_WORD, 0, 0
    write REGISTER_HARDWARE_VERSION_BYTE, HARDWARE_VERSION

    ; Generate unique hardware id (seed from sensor and battery readings)
    gosub read_RGBW_sensors
    calibadc10 tmp_word
    tmp_word = red * green * blue * white * tmp_word
    random tmp_word
    write REGISTER_UNIQUE_HW_ID_WORD1, word tmp_word
    tmp_word = red * green * blue * white * tmp_word
    random tmp_word
    write REGISTER_UNIQUE_HW_ID_WORD2, word tmp_word

    ; Mark first boot as passed
    tmp_word = FIRST_BOOT_PASS_WORD
    write REGISTER_FIRST_BOOT_PASS_WORD, word tmp_word
    return

zero_light_goal:
    write REGISTER_LIGHT_GOAL_WORD, 0, 0
    return

default_light_calibration:
    ; Default calibration using full spectrum white light measured at room temp.
    ; Copies table bytes into matching memory data address 15 onwards
	for tmp_low_byte = 15 to 39
		readtable tmp_low_byte, tmp_high_byte
		write tmp_low_byte, tmp_high_byte
	next tmp_low_byte
    return

comms_speed:
    ; 19200 comms to save power during sync
    setfreq m16 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    hi2csetup i2cmaster, EEPROM_24LC512, i2cfast_16, i2cword
    return

normal_speed:
    ; Sensor read and average i2c write loop
    setfreq m1 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    hi2csetup i2cmaster, EEPROM_24LC512, i2cfast, i2cword
    return

low_speed:
    ; Simulate low power sleep
    setfreq k31 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    return
