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
;                            C.4 -|3  12|- B.1 Red ADC
;                            C.3 -|4  11|- B.2 Green ADC
;                            C.2 -|5  10|- B.3 hi2c scl
;                            C.1 -|6   9|- B.4 hi2c sda
;                        LED C.0 -|7   8|- B.5 Blue ADC
;                                  –––––
; CHANGE LOG:
; v4 ...
; v3 Fixed (maybe) bugs with for loops near max int
; v2 Corrected for full 64K
; v1 Kinda working
;
; TODO:
; - Continue from last record after loss of power
; - When full, compress data 50% and double number of samples per average save
; - Calculate and store sample varience
; - Test fill and read back full 64K eprom
; - How should I trigger data dump? Sense serial connection? Serial signal from logging app?

#no_data ; <---- test this (programming should not zap eprom data)
#picaxe 14m2

init:
    ;setfreq m1
    hi2csetup i2cmaster, %10100000, i2cfast, i2cword

    symbol red = w0
    symbol green = w1
    symbol blue = w2
    symbol red_avg = w3
    symbol green_avg = w4
    symbol blue_avg = w5

    symbol i = w6
    symbol i1 = b12 ; lower byte of i word
    symbol i2 = b13 ; upper byte of i word

    symbol j = w7
    symbol j1 = b14 ; lower byte of j word
    symbol j2 = b15 ; upper byte of j word

    symbol red_byte = b16
    symbol green_byte = b17
    symbol blue_byte = b18
    symbol extra_byte = b19
    symbol test_read = b20

    ; LED off
    low C.0

    ; Pre-fill rolling averages
    readadc10 B.1, red_avg
    readadc10 B.2, green_avg
    readadc10 B.5, blue_avg

main:
    ; Datadump after a powercycle
    ;goto data_dump
    ;goto data_erase

data_log:
    for i = 0 to 65531 step 4
        ; Gather readings
        pulsout C.0, 100
        for j = 0 to 9
            readadc10 B.1, red
            readadc10 B.2, green
            readadc10 B.5, blue

            ; Calculate rolling averages
            red_avg = red_avg / 2
            red_avg = red / 2 + red_avg
            green_avg = green_avg / 2
            green_avg = green / 2 + green_avg
            blue_avg = blue_avg / 2
            blue_avg = blue / 2 + blue_avg

            ; Save some power
            disablebod
            sleep 1 ; 2.3sec per sample
            enablebod
        next j

        ; Store least significant bytes
        red_byte = red_avg & %11111111
        green_byte = green_avg & %11111111
        blue_byte = blue_avg & %11111111

        ; Fill extra_byte with 10bit excess rgb bits
        extra_byte = red_avg & %1100000000 / 256
        extra_byte = green_avg & %1100000000 / 64 + extra_byte
        extra_byte = blue_avg & %1100000000 / 16 + extra_byte

        ; Write sample to eprom (FIXME: 4x255 padding is a quick fix for eof)
        hi2cout i, (red_byte, green_byte, blue_byte, extra_byte, 255, 255, 255, 255)

        ; Read sample back in from eprom to test!
        ;pause 5
        ;hi2cin i, (red_byte, green_byte, blue_byte, extra_byte)
        ;sertxd(#i, ":", #red_byte, ",", #green_byte, ",", #blue_byte, ",", #extra_byte, 13)

        ; Write position to eprom
        write 0, WORD i
        ;read 0, WORD j
        ;sertxd("Position ", #j, 13)
        ;hi2cout 0, (i1, i2)
        ;sertxd("Position ", #i, ", ", #i1, ", ", #i2, 13)

        ; Read it back in from eprom to test!
        ;hi2cin 0, (j1, j2)
        ;sertxd("Samples ", #j, ", ", #j1, ", ", #j2, 13)
    next i

    goto data_log

data_dump:
    ; Output eprom data
    sleep 4
    ;read 0, WORD j
    ;sertxd("Samples ", #j, 13)
    ;hi2cin 0, (j1, j2)
    ;sertxd("Samples ", #j, ", ", #j1, ", ", #j2, 13)
    ;for i = 0 to j step 4
    for i = 0 to 65531 step 4
        hi2cin i, (red_byte, green_byte, blue_byte, extra_byte)
        if red_byte = 255 and green_byte = 255 and blue_byte = 255 and extra_byte = 255 then
            exit
        endif
        sertxd(#red_byte, ",", #green_byte, ",", #blue_byte, ",", #extra_byte, 13)
    next i
    end

data_erase:
    ; Erase eprom data (help with debugging)
    sleep 4
    sertxd("Erasing data ")
    for i = 0 to 65534
        hi2cout i, (255)
        hi2cin i, (test_read)
        if test_read != 255 then
            sertxd("Error:", #test_read, "@", #i)
        endif
        j = i % 255
        if j = 0 then
            sertxd(#i, ", ")
        endif
    next
    sertxd(13, "All data erased", 13)
    end
