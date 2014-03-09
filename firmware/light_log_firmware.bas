;Copyright (c) 2013, Gary C. Martin <gary@lightlogproject.org>
;All rights reserved.
;
;Redistribution and use in source and binary forms, with or without
;modification, are permitted provided that the following conditions are met:
;
;1. Redistributions of source code must retain the above copyright notice, this
;   list of conditions and the following disclaimer.
;
;2. Redistributions in binary form must reproduce the above copyright notice,
;   this list of conditions and the following disclaimer in the documentation
;   and/or other materials provided with the distribution.
;
;THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
;LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;POSSIBILITY OF SUCH DAMAGE.
;
;
; 14M2 ADC inputs for RGB light level logging to i2c 64K eprom
;                                  _____
;                             +V -|1 ^14|- 0V
;               In/Serial In C.5 -|2  13|- B.0 Serial Out/Out/hserout/DAC
;           Touch/ADC/Out/In C.4 -|3  12|- B.1 In/Out/ADC/Touch/SRI/hserin
;                         In C.3 -|4  11|- B.2 In/Out/ADC/Touch/pwm/SRQ
;     kbclk/hpwmA/pwm/Out/In C.2 -|5  10|- B.3 In/Out/ADC/Touch/hi2c scl
;        kbdata/hpwmB/Out/In C.1 -|6   9|- B.4 In/Out/ADC/Touch/pwm/hi2c sda
; hpwmC/pwm/Touch/ADC/Out/In C.0 -|7   8|- B.5 In/Out/ADC/Touch/hpwmD
;                                  –––––
;                                  _____
;                             +V -|1 ^14|- 0V
;               In/Serial In C.5 -|2  13|- B.0 Serial Out/Out/hserout/DAC
;             Sensors enable C.4 -|3  12|- B.1 Red ADC
;                     Button C.3 -|4  11|- B.2 Green ADC
;                            C.2 -|5  10|- B.3 hi2c scl
;                        LED C.1 -|6   9|- B.4 hi2c sda
;                  Clear ADC C.0 -|7   8|- B.5 Blue ADC
;                                  –––––
;
; TODO:
; - Can I software calibrate the sensor response curves as part of first init tests?
; - Can I software calibrate the case led reflection value (for various case designs)?
; - Add code for clear LDR sensor
; - When full, compress data 50% and double number of samples per average and continue
; - Extend two way serial protocol:
;   - log start time (and transmit it during sync)
;   - generate device id for first boot (and transmit it during sync)
;   - report hardware version in status (store in picaxe rom, defined during first run)
;   - add a validate/checksum to sync process
; - Calculate and store average samples varience (indication of activity)?
; - HW: Use external RTC?
; - HW: Move B.1 for use of hardware serial in?
; - HW: Pull down all unused inputs to 0V, e.g. with 100K or even 1M resistors.
; - HW: Current-limit any outputs to the degree possible. (e.g. LEDs)
; - Use a button to interrupt, short press for marker, long hold for reboot

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
    disconnect ; will need to power cycle to send upload program

    ; I2C setup
    hi2csetup i2cmaster, %10100000, i2cfast, i2cword

    symbol FIRMWARE_VERSION = 17
    symbol HARDWARE_VERSION = 3

    symbol LED = C.1
    symbol SENSOR_POWER = C.4
    symbol SENSOR_RED = B.1
    symbol SENSOR_GREEN = B.2
    symbol SENSOR_BLUE = B.5
    symbol SENSOR_TRANSPARENT = C.0
    symbol EVENT_BUTTON = pinC.3

    ; Button C.3 internal pullup resistor
    pullup %0000100000000000

    ; 5 = default, 63 = max (due to word int maths and avg)
    symbol SAMPLES_PER_AVERAGE = 5

    ; TODO: Check these realy work as expected and don't just point to pins!!!!!
    ;       Use #define instead if this is a bug?
    symbol FLAG_OK = %00000000
    symbol FLAG_REBOOT = %11000000
    symbol FLAG_BLOCKED = %01000000
    symbol FLAG_TBA = %10000000

    symbol REGISTER_LAST_SAVE_WORD = 0
    symbol REGISTER_REBOOT_COUNT_WORD = 2
    symbol REGISTER_HARDWARE_VERSION_BYTE = 4
    symbol REGISTER_UNIQUE_HW_ID_WORD1 = 5
    symbol REGISTER_UNIQUE_HW_ID_WORD2 = 7
    symbol REGISTER_FIRST_BOOT_PASS_WORD = 9
    symbol REGISTER_LOG_START_TIME_WORD1 = 11
    symbol REGISTER_LOG_START_TIME_WORD2 = 13

    symbol FIRST_BOOT_PASS_WORD = %1110010110100111

    symbol red = w0
    symbol green = w1
    symbol blue = w2
	symbol transparent = w3
    symbol red_avg = w4
    symbol green_avg = w5
    symbol blue_avg = w6
    symbol transparent_avg = w7
    symbol index = w8
    symbol tmp = w9

    symbol red_byte = b20
    symbol green_byte = b21
    symbol blue_byte = b22
    symbol extra_byte = b23
    symbol ser_in_byte = b24
    symbol flag = b25
    symbol sample_loop = b26
	symbol scratch = b27

    ; LED and sensors off
    low LED
    low SENSOR_POWER

	; First boot check
    read REGISTER_FIRST_BOOT_PASS_WORD, WORD tmp
    if tmp != FIRST_BOOT_PASS_WORD then
        write REGISTER_HARDWARE_VERSION_BYTE, HARDWARE_VERSION
        tmp = 0
        write REGISTER_REBOOT_COUNT_WORD, WORD tmp
        write REGISTER_LAST_SAVE_WORD, WORD tmp
        write REGISTER_LOG_START_TIME_WORD1, WORD tmp
        write REGISTER_LOG_START_TIME_WORD2, WORD tmp

        ; Generate unique hardware id (seed from sensor and battery readings)
        high SENSOR_POWER
        readadc10 SENSOR_RED, red
        readadc10 SENSOR_GREEN, green
        readadc10 SENSOR_BLUE, blue
        readadc10 SENSOR_TRANSPARENT, transparent
        low SENSOR_POWER
        calibadc10 tmp
        tmp = red * green * blue * transparent * tmp
        random tmp
        write REGISTER_UNIQUE_HW_ID_WORD1, WORD tmp
        tmp = red * green * blue * transparent * tmp
        random tmp
        write REGISTER_UNIQUE_HW_ID_WORD2, WORD tmp

        #ifdef DEBUG_FIRST_BOOT
            gosub high_speed
            sertxd("*** First boot ***", 13)
            read REGISTER_UNIQUE_HW_ID_WORD1, WORD tmp
            sertxd("Unique HW ID: ", #tmp)
            read REGISTER_UNIQUE_HW_ID_WORD2, WORD tmp
            sertxd(", ", #tmp, 13)
            gosub low_speed
        #endif

        ; Mark first boot as passed
        tmp = FIRST_BOOT_PASS_WORD
		write REGISTER_FIRST_BOOT_PASS_WORD, WORD tmp
	endif

    ; Keep a count of device reboots
    read REGISTER_REBOOT_COUNT_WORD, WORD tmp
    tmp = tmp + 1
    write REGISTER_REBOOT_COUNT_WORD, WORD tmp

    gosub power_on_animation

    flag = FLAG_REBOOT

main:
    for sample_loop = 1 to SAMPLES_PER_AVERAGE
        high SENSOR_POWER ; Sensors on
        readadc10 SENSOR_RED, red
        readadc10 SENSOR_GREEN, green
        readadc10 SENSOR_BLUE, blue
        readadc10 SENSOR_TRANSPARENT, transparent
        low SENSOR_POWER ; Sensors off

        if sample_loop = 1 then
            ; Pre-fill averages for first pass
            red_avg = red
            green_avg = green
            blue_avg = blue
            transparent_avg = transparent
        else
            ; Accumulate average data samples
            red_avg = red + red_avg
            green_avg = green + green_avg
            blue_avg = blue + blue_avg
            transparent_avg = transparent + transparent_avg
        endif

        #ifdef DEBUG_SENSORS
            gosub high_speed
            sertxd("Sensors: R=", #red, ", G=", #green, ", B=", #blue, ", T=", #transparent, 13)
            gosub low_speed
        #endif

        gosub check_user_button
        gosub check_serial_comms
        gosub low_power_and_delay
    next sample_loop

    ; Calculate averages
    red_avg = red_avg / SAMPLES_PER_AVERAGE
    green_avg = green_avg / SAMPLES_PER_AVERAGE
    blue_avg = blue_avg / SAMPLES_PER_AVERAGE
    transparent_avg = transparent_avg / SAMPLES_PER_AVERAGE

    ; Store least significant bytes
    red_byte = red_avg & %11111111
    green_byte = green_avg & %11111111
    blue_byte = blue_avg & %11111111

    ; Fill extra_byte with 9th and 10th bits from each rgb
    extra_byte = red_avg & %1100000000 / 256
    extra_byte = green_avg & %1100000000 / 64 + extra_byte
    extra_byte = blue_avg & %1100000000 / 16 + extra_byte

    ; Use extra_byte's 2 unsed bits for signaling
    extra_byte = extra_byte + flag
    flag = FLAG_OK ; Clear any flag states

    ; Write data to eprom
    read REGISTER_LAST_SAVE_WORD, WORD index
    hi2cout index, (red_byte, green_byte, blue_byte, extra_byte)

    ; Debug sensor output
    #ifdef DEBUG_WRITE
        gosub high_speed
        sertxd("Write to ", #index, ", R=", #red_byte, ", G=", #green_byte, ", B=", #blue_byte, ", E", #extra_byte, 13)
        gosub low_speed
    #endif

    ; Increment and write position to micro eprom (mem bytes = 65536)
    index = index + 4
    write REGISTER_LAST_SAVE_WORD, WORD index

    goto main

low_power_and_delay:
    ; Save power and sleep
    sleep 2 ; 1 = 2.3sec watchdog timer
    return

check_user_button:
    if EVENT_BUTTON = 0 then
        gosub pulse_led
        gosub pulse_led
        gosub pulse_led
        gosub high_speed
        gosub display_status
        gosub low_speed
    endif

    #ifdef DEBUG_BUTTON
        gosub high_speed
        if EVENT_BUTTON = 0 then
            sertxd("Button ON", 13)
        else
            sertxd("Button OFF", 13)
        endif
        gosub low_speed
    #endif
    return

check_serial_comms:
    gosub high_speed
    sertxd("Hello?")
    serrxd [120, serial_checked], ser_in_byte
    ;serrxd [100, serial_checked], ("cmd"), ser_in_byte
    ;serrxd ser_in_byte

    if ser_in_byte = "a" then
        gosub display_status

    elseif ser_in_byte = "b" then
        gosub dump_data_and_reset_pointer

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

    else
        sertxd("Error ", #ser_in_byte, 13)

    endif

serial_checked:
    gosub low_speed
    return

power_on_animation:
    ; Get some attention
    for scratch = 1 to 5
        gosub pulse_led
    next scratch
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
	read REGISTER_HARDWARE_VERSION_BYTE, tmp
    sertxd("Hardware version: ", #tmp, 13)
    read REGISTER_UNIQUE_HW_ID_WORD1, WORD tmp
    sertxd("Unique hardware ID: ", #tmp)
    read REGISTER_UNIQUE_HW_ID_WORD2, WORD tmp
    sertxd(", ", #tmp, 13)
    sertxd("Firmware version: ", #FIRMWARE_VERSION, 13)
    read REGISTER_REBOOT_COUNT_WORD, WORD tmp
    sertxd("Device reboot count: ", #tmp, 13)
    read REGISTER_LAST_SAVE_WORD, WORD index
    sertxd("Mem pointer: ", #index, "/65536", 13)
	read REGISTER_LOG_START_TIME_WORD1, WORD tmp
    sertxd("Log start: ", #tmp)
	read REGISTER_LOG_START_TIME_WORD2, WORD tmp
    sertxd(", ", #tmp, 13)
    calibadc10 tmp
    tmp = 52378 / tmp * 2
    sertxd("Batttey: ", #tmp, "0mV", 13)
    sertxd("Sensors: R=", #red, ", G=", #green, ", B=", #blue, ", T=", #transparent, 13)
    return

dump_data_and_reset_pointer:
    ; Output eprom data and reset pointer
    read REGISTER_LAST_SAVE_WORD, WORD index
    if index != 0 then
	    index = index - 4
    endif
    for tmp = 0 to index step 4
        hi2cin tmp, (red_byte, green_byte, blue_byte, extra_byte)
        sertxd (red_byte, green_byte, blue_byte, extra_byte)
    next tmp
    sertxd("eof")
    gosub reset_pointer
    return

dump_data:
    ; Debug output data
    read REGISTER_LAST_SAVE_WORD, WORD index
    if index != 0 then
	    index = index - 4
    endif
    for tmp = 0 to index step 4
        hi2cin tmp, (red_byte, green_byte, blue_byte, extra_byte)
        sertxd (red_byte, green_byte, blue_byte, extra_byte)
    next tmp
    sertxd("eof")
    return

dump_all_eprom_data:
    ; Debug output all eprom data
    for tmp = 0 to 65531 step 4
        hi2cin tmp, (red_byte, green_byte, blue_byte, extra_byte)
        sertxd (red_byte, green_byte, blue_byte, extra_byte)
    next tmp
    sertxd("eof")
    return

reset_pointer:
    index = 0 ; reset pointer back to start of mem
    write REGISTER_LAST_SAVE_WORD, WORD index
    return

reset_reboot_counter:
    tmp = 0
    write 2, WORD tmp ; reset reboot counter back to 0
    return

erase_all_data:
    ; Debug erase eprom data (help with debugging)
    for tmp = 0 to 65534
        hi2cout tmp, (255)
    next tmp
    gosub reset_pointer
    gosub reset_reboot_counter
    return

high_speed:
    setfreq m32; k31, k250, k500, m1, m2, m4, m8, m16, m32
    hi2csetup i2cmaster, %10100000, i2cfast_32, i2cword
    return

low_speed:
    setfreq k500; k31, k250, k500, m1, m2, m4, m8, m16, m32
    hi2csetup i2cmaster, %10100000, i2cfast, i2cword
    return
