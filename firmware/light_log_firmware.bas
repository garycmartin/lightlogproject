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
; PICAXE 08M2 ADC inputs for RGB light level logging
;                        _____
;                   +V -|1 ^ 8|- 0V
;     In/Serial In C.5 -|2   7|- C.0 Serial Out/Out/hserout/DAC
; Touch/ADC/Out/In C.4 -|3   6|- C.1 In/Out/ADC/Touch/hserin/SRI/hi2c scl
;               In C.3 -|4   5|- C.2 In/Out/ADC/Touch/pwm/tune/SRQ/hi2c sda
;                        –––––
;
;                        _____
;                   +V -|1 ^ 8|- 0V
;     In/Serial In C.5 -|2   7|- C.0 Data out to audio jack?
;      Blue ADC in C.4 -|3   6|- C.1 Red ADC in
;               In C.3 -|4   5|- C.2 Green ADC in
;                        –––––

#picaxe 08m2

init:
    setfreq m1
    symbol red = b0
    symbol green = b1
    symbol blue = b2
    symbol i = b3
    symbol addr = b4
    symbol j = b5
    symbol red_w = w3
    symbol green_w = w4
    symbol blue_w = w5

main:
    for i = 0 to 255 step 3
        red_w = 0
        green_w = 0
        blue_w = 0
        ; Gather average readings
        for j = 0 to 5
            readadc C.1, red
            readadc C.2, green
            readadc C.4, blue
            sertxd(#red, ",", #green, ",", #blue, 13)
            red_w = red_w + red
            green_w = green_w + green
            blue_w = blue_w + blue
            ; 4 = ten seconds between samples (2.3sec per unit)
            ;disablebod
            ;sleep 4
            ;enablebod
        next j
        red = red_w / 6
        green = green_w / 6
        blue = blue_w / 6
        addr = i
        write addr, red
        addr = addr + 1
        write addr, green
        addr = addr + 1
        write addr, blue
    next
    goto main