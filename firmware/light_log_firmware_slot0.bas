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
                  Serial In C.5 -|2  13|- B.0 Serial Out
               SENSOR_POWER C.4 -|3  12|- B.1 LED5
               EVENT_BUTTON C.3 -|4  11|- B.2 LED4
               EEPROM_POWER C.2 -|5  10|- B.3 hi2c scl
                       LED1 C.1 -|6   9|- B.4 hi2c sda
                       LED2 C.0 -|7   8|- B.5 LED3
                                  –––––
#endrem

#slot 0
#no_data ; Make sure re-programming does not wipe eeprom data memory
#no_end
#picaxe 14m2

symbol FIRMWARE_VERSION = 22

; 4 = SMT v0.6 Rev A-B in case with small sensor window
; 5 = SMT v0.6 Rev A-B in case with large sensor window
symbol HARDWARE_VERSION = 5
symbol EEPROM_POWER = C.2
symbol SENSOR_POWER = C.4
symbol LED1 = C.1
symbol LED2 = C.0
symbol LED3 = B.5
symbol LED4 = B.2
symbol LED5 = B.1
symbol EVENT_BUTTON = pinC.3

; 63 = max (due to word int maths and avg overflow risk)
symbol DEFAULT_SAMPLES_PER_AVERAGE = 6
symbol DEFAULT_2SEC_DELAY = 1000

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

symbol REGISTER_DELAY_WORD = 56
symbol REGISTER_SAMPLES_PER_AVERAGE = 58

symbol BYTES_PER_RECORD = 6
symbol EEPROM_WRAP = 65529 ; 65535 - 6

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

; Volatile microprecessor memory
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
symbol VAR_WHITE_ORIGINAL_WORD = 28
symbol VAR_SLOT_STATE_CHECK = 30

symbol SLOT_NULL = 0
symbol SLOT_MAIN_SAMPLE_LOOP = 1
symbol SLOT_STORE_SAMPLES = 2
symbol SLOT_CHECK_SERIAL_COMMS = 3
symbol SLOT_UI_CHECK_AND_READ_RGBW = 4
symbol SLOT_FIRST_BOOT_INIT = 5

init:
    ; Save all the power we can
    disablebod ; disable 1.9V brownout detector
    disabletime ; Stop the time clock
    disconnect ; Don't listen for re-programming
    setfreq m1 ; k31, k250, k500, m1, m2, m4, m8, m16, m32

    ; Check for previous slot states
    peek VAR_SLOT_STATE_CHECK, tmp2_low_byte
    poke VAR_SLOT_STATE_CHECK, SLOT_NULL
    if tmp2_low_byte = SLOT_MAIN_SAMPLE_LOOP then
        goto main_sample_loop
    elseif tmp2_low_byte = SLOT_UI_CHECK_AND_READ_RGBW then
        gosub bargraph_display
        gosub UI_check_and_read_RGBW
        goto main_sample_loop
    endif

    ; Button C.3 internal pullup resistor
    pullup %0000100000000000

    ; First boot check
    read REGISTER_FIRST_BOOT_PASS_WORD, word tmp_word
    if tmp_word != FIRST_BOOT_PASS_WORD then
        ; Run first_boot_init code over in slot 1
        poke VAR_SLOT_STATE_CHECK, SLOT_FIRST_BOOT_INIT
        run 1
    endif

    ; Check delay is set to a reasonable value
    read REGISTER_DELAY_WORD, word tmp_word
    if tmp_word < 500 or tmp_word > 2000 then
        tmp_word = DEFAULT_2SEC_DELAY
        write REGISTER_DELAY_WORD, word tmp_word
    endif

    ; Check number of samples is set to a reasonable value
    read REGISTER_SAMPLES_PER_AVERAGE, tmp_low_byte
    if tmp_low_byte = 0 or tmp_low_byte > 64 then
        tmp_low_byte = DEFAULT_SAMPLES_PER_AVERAGE
        write REGISTER_SAMPLES_PER_AVERAGE, tmp_low_byte
    endif

    ; Keep a count of device reboots
    read REGISTER_REBOOT_COUNT_WORD, word tmp_word
    inc tmp_word
    write REGISTER_REBOOT_COUNT_WORD, word tmp_word

    gosub flash_led

    flag = FLAG_REBOOT

main_sample_loop:
    low EEPROM_POWER
    read REGISTER_SAMPLES_PER_AVERAGE, sample_loop
    gosub UI_check_and_read_RGBW

    ; Pre-fill averages for first pass
    red_avg = red
    green_avg = green
    blue_avg = blue
    white_avg = white
    pause 3

main_loop:
    dec sample_loop
    if sample_loop = 0 then
    	; Calculate averages and store samples to eeprom over in slot 1
        poke VAR_SLOT_STATE_CHECK, SLOT_STORE_SAMPLES
        run 1
    endif

    gosub UI_check_and_read_RGBW

    ; Accumulate average data samples
    red_avg = red + red_avg
    green_avg = green + green_avg
    blue_avg = blue + blue_avg
    white_avg = white + white_avg
    goto main_loop


UI_check_and_read_RGBW:
    setfreq k31 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    gosub check_user_button
    gosub check_user_button
    gosub check_user_button
    gosub check_user_button
    gosub check_user_button

read_RGBW_sensors:
    setfreq m1 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
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
    pause 44

    ; Idle once integration cycle completes <--- can I sleep here or above?
    hi2cout TCS34725FN_ENABLE, (%00000001)

    hi2cin TCS34725FN_CDATA, (tmp_low_byte, tmp_high_byte)

    ; Drop to 0 gain and resample if overexposed
    if tmp_word = 0xFFFF and tmp2_low_byte = 0 then
        tmp2_low_byte = 1
        hi2cout TCS34725FN_AGAIN, (0x00)
        goto too_bright_retry_entry_point
    endif

    ; Remember uncompressed white for use in rgb deltas 
    poke VAR_WHITE_ORIGINAL_WORD, word tmp_word

    gosub bit_compress
    white = tmp_word

    hi2cin TCS34725FN_RDATA, (tmp_low_byte, tmp_high_byte)
    gosub scale_into_10bits
    red = tmp_word

    hi2cin TCS34725FN_GDATA, (tmp_low_byte, tmp_high_byte)
    gosub scale_into_10bits
    green = tmp_word

    hi2cin TCS34725FN_BDATA, (tmp_low_byte, tmp_high_byte)

    ; Power off TCS34725FN light sensor
    low SENSOR_POWER

    gosub scale_into_10bits
    blue = tmp_word

    ; Correct timing if first sample was good (use low power)
    if tmp2_low_byte = 0 then
        setfreq k31
        pauseus 95
        setfreq m1
    endif

    ;sertxd("W", #white, ", R", #red, ", G", #green, ", B", #blue, 13)
    return


scale_into_10bits:
    ; Scale colour into a 10bit value based on white value as 100% (=1023)
    ; WARNING: blue variable being used as a tmp variable here
    blue = tmp_word
    peek VAR_WHITE_ORIGINAL_WORD, word tmp_word

    ; White should always be the larger rgb colour...
    if tmp_word = 0 then
        return
    elseif tmp_word < blue then
        tmp_word = blue
    endif

    ; Make the best out of integer maths
    if blue > 32768 then
        tmp_word = tmp_word / 1024 + 1
        tmp_word = blue / tmp_word
        ;tmp_word = tmp_word + 1 / 1024
        ;tmp_word = blue + 1 / tmp_word
    elseif blue > 16384 then
        tmp_word = tmp_word / 512 + 1
        tmp_word = blue * 2 - 1 / tmp_word
    elseif blue > 8192 then
        tmp_word = tmp_word / 256 + 1
        tmp_word = blue * 4 - 1 / tmp_word
    elseif blue > 4096 then
        tmp_word = tmp_word / 128 + 1
        tmp_word = blue * 8 - 1 / tmp_word
    elseif blue > 2048 then
        tmp_word = tmp_word / 64 + 1
        tmp_word = blue * 16 - 1 / tmp_word
    elseif blue > 1024 then
        tmp_word = tmp_word / 32 + 1
        tmp_word = blue * 32 - 1 / tmp_word
    elseif blue > 512 then
        tmp_word = tmp_word / 16 + 1
        tmp_word = blue * 64 - 1 / tmp_word
    elseif blue > 128 then
        tmp_word = tmp_word / 8 + 1
        tmp_word = blue * 128 - 1 / tmp_word
    elseif blue > 64 then
        tmp_word = tmp_word / 4 + 1
        tmp_word = blue * 256 - 1 / tmp_word
    elseif blue > 32 then
        tmp_word = tmp_word / 2 + 1
        tmp_word = blue * 512 - 1 / tmp_word
    else
        tmp_word = blue * 1024 - 1 / tmp_word
    endif

    ; Keep within 10bit range (int maths can exceed)
    if tmp_word > 1023 then
        tmp_word = 1023
    endif
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
            gosub idle_wait
            return
        endif
        inc tmp_word
        write REGISTER_BUTTON_LATCHED_WORD, word tmp_word
        flag = flag | FLAG_BUTTON

        ; User feedback based on current light level and goal
        gosub read_RGBW_sensors

        ; Use 19200 baud to save power during comms
        setfreq m16 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
        sertxd("Hello?")
        serrxd [150, serial_checked], ser_in_byte, tmp_low_byte, tmp_high_byte

            ; Serial comms detected, run slot 1's check_serial_comms
            poke VAR_SLOT_STATE_CHECK, SLOT_CHECK_SERIAL_COMMS
            run 1

        serial_checked:
        gosub bargraph_display
        setfreq k31 ; k31, k250, k500, m1, m2, m4, m8, m16, m32

    else
        write REGISTER_BUTTON_LATCHED_WORD, 0, 0
        gosub idle_wait
    endif
    return


bargraph_display:
    setfreq m1 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    ; Allow program upload during a button press
    reconnect

    ; Animate into bargraph display
    gosub flash_led

    ; Prevent program upload (saves power)
    disconnect

    ; Check if illumination is bright enough to count to goal
    read REGISTER_2_5KLUX_WHITE_WORD, word tmp_word
    if white >= tmp_word then
        tmp2_high_byte = 16
    else
        tmp2_high_byte = 48
    endif

    ; Display bar graph animation for daily goal progress
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
        if tmp_word = 60000 then
            low LED1, LED2, LED3, LED4, LED5
        endif
        pause tmp2_high_byte

    next tmp2_low_byte
    low LED1, LED2, LED3, LED4, LED5
    return


idle_wait:
    ; Delay for 2 sec without using the low power sleep watchdog timer 
    ; More accurate, avoids intermittent reboots, but uses more power
    read REGISTER_DELAY_WORD, word tmp_word

	; Time tweak bias based on code path changes
    tmp_word = tmp_word * 20 / 80

    pauseus tmp_word
    return


flash_led:
    ; Left to right LED sequence flash
    high LED5
    pause 8
    toggle LED5, LED4
    pause 8
    toggle LED4, LED3
    pause 8
    toggle LED3, LED2
    pause 8
    toggle LED2, LED1
    pause 8
    low LED1
    return