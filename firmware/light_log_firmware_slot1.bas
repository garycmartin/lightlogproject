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
#endrem

; Lux calibration table (copied into data memory on first boot or factory reset)
; Each sample is measured from a broard spectrum white SAD light source
; R_LOW, R_HIGH, G_LOW, G_HIGH, B_LOW, B_HIGH, C_LOW, C_HIGH @ 2.5k
; R_LOW, R_HIGH, G_LOW, G_HIGH, B_LOW, B_HIGH, C_LOW, C_HIGH @ 5k
; R_LOW, R_HIGH, G_LOW, G_HIGH, B_LOW, B_HIGH, C_LOW, C_HIGH @ 10k
table 15, (0x40, 0x01, 0x8D, 0x01, 0x27, 0x01, 0xFA, 0x02, _
           0x3A, 0x01, 0x8C, 0x01, 0x30, 0x01, 0x33, 0x03, _
           0x3E, 0x01, 0x8E, 0x01, 0x2B, 0x01, 0x56, 0x03)

#slot 1
#no_data ; Make sure re-programming does not wipe eeprom data memory
#no_end
#picaxe 14m2

symbol FIRMWARE_VERSION = 21

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

; TODO: is lux calibration working as expected, values looked wrong.

init:
    ; Save all the power we can
    disablebod ; disable 1.9V brownout detector
    disabletime ; Stop the time clock
    disconnect ; Don't listen for re-programming
    setfreq m1 ; k31, k250, k500, m1, m2, m4, m8, m16, m32

    ; Check for previous slot states
    peek VAR_SLOT_STATE_CHECK, tmp2_low_byte
    poke VAR_SLOT_STATE_CHECK, SLOT_NULL
    if tmp2_low_byte = SLOT_STORE_SAMPLES then
        goto store_samples

    elseif tmp2_low_byte = SLOT_FIRST_BOOT_INIT then
        goto first_boot_init

    elseif tmp2_low_byte = SLOT_CHECK_SERIAL_COMMS then
        goto check_serial_comms
    endif

    ; Run slot 0 if null or unknown state found (can happen after re-program)
    run 0


store_samples:
    setfreq m1 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    ; Calculate averages
    read REGISTER_SAMPLES_PER_AVERAGE, tmp_low_byte
    red_avg = red_avg / tmp_low_byte
    green_avg = green_avg / tmp_low_byte
    blue_avg = blue_avg / tmp_low_byte
    white_avg = white_avg / tmp_low_byte

    high EEPROM_POWER
    hi2csetup i2cmaster, EEPROM_24LC512, i2cfast, i2cword

    ;sertxd("WA", #white_avg, ", RA", #red_avg, ", GA", #green_avg, ", BA", #blue_avg, 13)

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
    inc tmp_word
    if tmp_word >= 1440 then
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
    pause 2
    inc tmp_word

    green_byte = green_avg & %11111111
    hi2cout tmp_word, (green_byte)
    pause 2
    inc tmp_word

    blue_byte = blue_avg   & %11111111
    hi2cout tmp_word, (blue_byte)
    pause 2
    inc tmp_word

    white_byte = white_avg & %11111111
    hi2cout tmp_word, (white_byte)
    pause 2
    inc tmp_word

    ; Fill extra_byte with 9th and 10th bits of each RGBT
    extra_byte = red_avg   & %1100000000 / 256
    extra_byte = green_avg & %1100000000 / 64 + extra_byte
    extra_byte = blue_avg  & %1100000000 / 16 + extra_byte
    extra_byte = white_avg & %1100000000 / 4  + extra_byte

    hi2cout tmp_word, (extra_byte)
    pause 2
    inc tmp_word

    hi2cout tmp_word, (flag)
    pause 2
    inc tmp_word

    ;sertxd("WB", #white_byte, ", RB", #red_byte, ", GB", #green_byte, ", BB", #blue_byte, ", EB", #extra_byte, 13)

    flag = FLAG_OK ; Clear any flag states

    ; Increment and write current position to micro eprom
    if tmp_word >= EEPROM_WRAP then
        write REGISTER_LAST_SAVE_WORD, 0, 0

        ; Keep track of memory wraps
        read REGISTER_MEMORY_WRAPPED_WORD, word tmp_word
        inc tmp_word
        write REGISTER_MEMORY_WRAPPED_WORD, word tmp_word

    else
        write REGISTER_LAST_SAVE_WORD, word tmp_word
    endif

    low EEPROM_POWER

    poke VAR_SLOT_STATE_CHECK, SLOT_MAIN_SAMPLE_LOOP
    run 0


check_serial_comms:
    setfreq m16 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    select case ser_in_byte
        case "a"
        gosub header_block

        case "c"
        gosub dump_data

        case "e"
        gosub reset_pointer

        case "h"
        gosub calibrate_2_5Klux

        case "i"
        gosub calibrate_5Klux

        case "j"
        gosub calibrate_10Klux

        case "k"
        gosub default_light_calibration

        case "l"
        gosub zero_light_goal

        case "d"
        gosub set_time_delay

        case "p"
        gosub set_day_phase

        case "s"
        gosub set_samples_per_average

        case "z"
        gosub first_boot_init
    endselect

    ; Note: this sample cycle will have been disrupted by the comms activity
    poke VAR_SLOT_STATE_CHECK, SLOT_UI_CHECK_AND_READ_RGBW
    run 0


set_time_delay:
    ; Used to fine tune device delay
    write REGISTER_DELAY_WORD, word tmp_word
    return


set_samples_per_average:
    ; 1 sample every 10 sec, defaults to 6 samples per average = 1 per min
    write REGISTER_SAMPLES_PER_AVERAGE, tmp_low_byte
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
    read REGISTER_SAMPLES_PER_AVERAGE, tmp2_low_byte
    tmp2_word = tmp2_low_byte * 10
    sertxd("Period:", #tmp2_word, ";")
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
    read REGISTER_DELAY_WORD, word tmp2_word
    sertxd("Delay:", #tmp2_word, ";")
    calibadc10 tmp2_word
    tmp2_word = 52378 / tmp2_word * 2
    sertxd("Batt:", #tmp2_word, "0mV", ";")
    setfreq m1 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    high SENSOR_POWER
    calibadc10 tmp2_word
    low SENSOR_POWER
    setfreq m16 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    tmp2_word = 52378 / tmp2_word * 2
    sertxd("BattSen:", #tmp2_word, "0mV", ";")
    setfreq k31 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    calibadc10 tmp2_word
    setfreq m16 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    tmp2_word = 52378 / tmp2_word * 2
    sertxd("BattSlp:", #tmp2_word, "0mV", ";")
    sertxd("RGBW:", #red, ",", #green, ",", #blue, ",", #white)
    sertxd("head_eof")
    return


set_day_phase:
    ; Update day phase (crude test to check the value is at least sane)
    if tmp_word < 1440 then
        read REGISTER_DAY_PHASE_WORD, word tmp2_word
        ; Try and estimate if daily accumulated goal should be reset
        if tmp2_word > 1080 and tmp_word < 360 then
            gosub zero_light_goal
        endif
        write REGISTER_DAY_PHASE_WORD, word tmp_word
    endif
    return


dump_data:
    ; Output data oldest to newest
    high EEPROM_POWER
    hi2csetup i2cmaster, EEPROM_24LC512, i2cfast_16, i2cword
    gosub header_block
    gosub set_day_phase ; serial comms word passed via tmp_word
    read REGISTER_MEMORY_WRAPPED_WORD, word tmp_word
    if tmp_word > 0 then
        ; Dump end block of memory first if memory has wrapped one or more times
        gosub dump_from_index_to_end
    endif
    gosub dump_up_to_index
    low EEPROM_POWER
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
    for tmp2_word = tmp_word to EEPROM_WRAP step BYTES_PER_RECORD
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


first_boot_init:
    setfreq m1 ; k31, k250, k500, m1, m2, m4, m8, m16, m32
    ; Factory reset
    gosub default_light_calibration
    gosub reset_pointer
    write REGISTER_REBOOT_COUNT_WORD, 0, 0
    gosub zero_light_goal
    write REGISTER_DAY_PHASE_WORD, 0, 0
    write REGISTER_HARDWARE_VERSION_BYTE, HARDWARE_VERSION
    tmp_word = DEFAULT_2SEC_DELAY
    gosub set_time_delay
    tmp_low_byte = DEFAULT_SAMPLES_PER_AVERAGE
    gosub set_samples_per_average

    ; Generate unique hardware id (seed from sensor, battery, temp readings)
    calibadc10 tmp_word
    random tmp_word
    high SENSOR_POWER
    hi2csetup i2cmaster, TCS34725FN, i2cfast, i2cbyte
    hi2cout TCS34725FN_ATIME, (0xC0)
    pause 3
    hi2cout TCS34725FN_AGAIN, (0x02) ; 0x02=16x gain
    pause 4
    hi2cout TCS34725FN_ENABLE, (%00000001)
    pause 4
    hi2cout TCS34725FN_ENABLE, (%00000011)
    pause 44
    hi2cout TCS34725FN_ENABLE, (%00000001)
    hi2cin TCS34725FN_CDATA, (tmp2_low_byte, tmp2_high_byte)
    tmp_word = 1 + tmp2_word * tmp_word
    random tmp_word
    hi2cin TCS34725FN_RDATA, (tmp2_low_byte, tmp2_high_byte)
    tmp_word = 1 + tmp2_word * tmp_word
    random tmp_word
    hi2cin TCS34725FN_GDATA, (tmp2_low_byte, tmp2_high_byte)
    tmp_word = 1 + tmp2_word * tmp_word
    random tmp_word
    hi2cin TCS34725FN_BDATA, (tmp2_low_byte, tmp2_high_byte)
    tmp_word = 1 + tmp2_word * tmp_word
    low SENSOR_POWER
    random tmp_word
    write REGISTER_UNIQUE_HW_ID_WORD1, word tmp_word
    readinternaltemp IT_RAW_L, 0, tmp2_word
    tmp_word = 1 + tmp2_word * tmp_word
    random tmp_word
    write REGISTER_UNIQUE_HW_ID_WORD2, word tmp_word

    ; Mark first boot as passed
    tmp_word = FIRST_BOOT_PASS_WORD
    write REGISTER_FIRST_BOOT_PASS_WORD, word tmp_word

    poke VAR_SLOT_STATE_CHECK, SLOT_NULL
    run 0


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
