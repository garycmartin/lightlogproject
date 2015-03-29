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

#slot 1
#no_data ; Make sure re-programming does not zap eeprom data memory
#picaxe 14m2

; Run slot 0 if not triggered from slot 0 (can happen after a slot re-program)
symbol REGISTER_CHECK_SLOT_1 = 55
symbol tmp_low_byte = b16
read REGISTER_CHECK_SLOT_1, tmp_low_byte
if tmp_low_byte != 2 then
    write REGISTER_CHECK_SLOT_1, 0
    run 0
endif

; Save all the power we can
disablebod ; disable 1.9V brownout detector
disabletime ; Stop the time clock
disconnect ; Don't listen for re-programming
setfreq m1 ; k31, k250, k500, m1, m2, m4, m8, m16, m32

init:
    symbol EEPROM_POWER = C.2

    symbol FLAG_OK = %00000000
    symbol REGISTER_LAST_SAVE_WORD = 0
    ; Populated by table at address 15 on first boot
    symbol REGISTER_2_5KLUX_WHITE_WORD = 21
    symbol REGISTER_5KLUX_WHITE_WORD = 29
    symbol REGISTER_10KLUX_WHITE_WORD = 37

    symbol REGISTER_LIGHT_GOAL_WORD = 47
    symbol REGISTER_DAY_PHASE_WORD = 49
    symbol REGISTER_MEMORY_WRAPPED_WORD = 51

    symbol REGISTER_SAMPLES_PER_AVERAGE = 58

    symbol BYTES_PER_RECORD = 6
    symbol EEPROM_TOTAL_BYTES = 65536
    symbol END_EEPROM_ADDRESS = EEPROM_TOTAL_BYTES - 1
    symbol BYTE_GAP_AT_END = EEPROM_TOTAL_BYTES % BYTES_PER_RECORD
    symbol GAP_PLUS_RECORD = BYTE_GAP_AT_END + BYTES_PER_RECORD
    symbol LAST_VALID_RECORD = END_EEPROM_ADDRESS - GAP_PLUS_RECORD
    symbol LAST_VALID_BYTE = END_EEPROM_ADDRESS - BYTE_GAP_AT_END

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
    ;symbol tmp_low_byte = b16
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

main:
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
    inc tmp_word

    green_byte = green_avg & %11111111
    hi2cout tmp_word, (green_byte)
    inc tmp_word

    blue_byte = blue_avg   & %11111111
    hi2cout tmp_word, (blue_byte)
    inc tmp_word

    white_byte = white_avg & %11111111
    hi2cout tmp_word, (white_byte)
    inc tmp_word

    ; Fill extra_byte with 9th and 10th bits of each RGBT
    extra_byte = red_avg   & %1100000000 / 256
    extra_byte = green_avg & %1100000000 / 64 + extra_byte
    extra_byte = blue_avg  & %1100000000 / 16 + extra_byte
    extra_byte = white_avg & %1100000000 / 4  + extra_byte

    hi2cout tmp_word, (extra_byte)
    inc tmp_word

    hi2cout tmp_word, (flag)
    inc tmp_word

    ;sertxd("WB", #white_byte, ", RB", #red_byte, ", GB", #green_byte, ", BB", #blue_byte, ", EB", #extra_byte, 13)

    flag = FLAG_OK ; Clear any flag states

    ; Increment and write current position to micro eprom
    if tmp_word >= LAST_VALID_RECORD then
        write REGISTER_LAST_SAVE_WORD, 0, 0

        ; Keep track of memory wrapps
        read REGISTER_MEMORY_WRAPPED_WORD, word tmp_word
        inc tmp_word
        write REGISTER_MEMORY_WRAPPED_WORD, word tmp_word

    else
        write REGISTER_LAST_SAVE_WORD, word tmp_word
    endif

    write REGISTER_CHECK_SLOT_1, 1
    run 0