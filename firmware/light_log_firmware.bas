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
; v11 Fixed light block test
;     Light led only when it gets darker than average
;     Light led if previous result was "blocked", light it 3 times to tripple check
; v10 Testing for back reflection from LED to indicate sensors are blocked
;     Serial ping 'Hello?' to trigger remote sync if connected
; v9  Converted data sync format from asci to raw bytes for speed
;     Power saving tweaks, low speed, no brownout, no time, don't listen for prog
;     Commands designed for realtime client software use (not human keyboarding)
;     Less samples, longer gap between
; v8  Fixed i2c fault at higher than m8 clock speeds
;     Log data now dumped at m32 (with client connection at 38400 baud)
; v7  Improved avarages (no roll over between saved samples, more accurate)
;     Code cleanup
;     Added dump data and continue test routine
;     Added serial cmd commands
;     Dropped to 2Mhz = serial 2400bps (any slower seems to make serial io flakey)
;     Replaced 255,255,255,255 reboot with extra_byte 2-bit flag in data
;     High speed erase (should do this for data sync next)
; v6  Continues from last record on loss of power
;     Sensors VCC moved to C.4 allowing power down between samples
; v5  Stuff... (debugging mainly)
; v4  Minor tinkering...
; v3  Fixed (maybe) bugs with for loops near max int
; v2  Corrected for full 64K
; v1  Kinda working
;
; TODO:
; - When full, compress data 50% and double number of samples per average and continue
; - Two way serial coms for data download protocol, log start time, device id, time step
; - Calculate and store average samples varience (indication of activity?)
; - HW: Use external RTC?
; - HW: Move B.1 for use of hardware serial in?
; - HW: Pull down all unused inputs to 0V, e.g. with 100K or even 1M resistors.
; - HW: Current-limit any outputs to the degree possible. (e.g. LEDs)

#no_data ; <---- test this (re-programming should not zap eprom data)
#picaxe 14m2

init:
    gosub low_speed
    hi2csetup i2cmaster, %10100000, i2cfast, i2cword
    disablebod
    disabletime
    disconnect

    symbol red = w0
    symbol green = w1
    symbol blue = w2
    symbol red_avg = w3
    symbol green_avg = w4
    symbol blue_avg = w5
    symbol i = w6
    symbol j = w7
    symbol k = w8
    symbol l = w9

    symbol red_byte = b20
    symbol green_byte = b21
    symbol blue_byte = b22
    symbol extra_byte = b23
    symbol ser_in_byte = b24
    symbol flag = b25
    symbol scratch = b26
    symbol blocked = b27

    ; 9 = 10 sample every 23sec (Tue 15 Oct 2013 04:08:54 BST reset count = 8, 64, 71, 79, 81, ??)
    ; 99 = 100 sample every 230sec 50sec (Wed 2 Oct 2013 19:42:36 reset count = 22, 27, 33) <- 63 max!!
    ; 63 = 64 sample every 147.2sec 50sec (Wed 16 Oct 2013 02:50:36 reset count = 22, 27, 33)
    symbol SAMPLES_PER_AVERAGE = 5
    symbol FLAG_OK = %00000000
    symbol FLAG_REBOOT = %11000000
    symbol FLAG_BLOCKED = %01000000
    symbol FLAG_FOO = %10000000

    symbol LED = C.0
    symbol SENSOR_POWER = C.4
    symbol SENSOR_RED = B.1
    symbol SENSOR_GREEN = B.2
    symbol SENSOR_BLUE = B.5

    ; LED off
    low LED

    ; Sensors off
    low SENSOR_POWER

    ; Count reboots
    read 2, WORD k
    k = k + 1
    write 2, WORD k

    gosub flash_led
    gosub display_status

    ; Continue recording from last save and flag reboot
    read 0, WORD i
    flag = FLAG_REBOOT

    ; Three flashes of led on re-boot to test for obstruction
    blocked = 3

main:
    for j = 1 to SAMPLES_PER_AVERAGE
        high SENSOR_POWER ; Sensors on
        if j = 1 then
            ; Pre-fill averages
            readadc10 SENSOR_RED, l
            k = l * j
            if k <= red_avg or blocked > 0 then
                high LED
                nap 1
                readadc10 SENSOR_RED, k
                low LED
                nap 1
            else
                k = l
                low LED
                low LED
                nap 2
            endif
            readadc10 SENSOR_RED, red_avg
            readadc10 SENSOR_GREEN, green_avg
            readadc10 SENSOR_BLUE, blue_avg
        else
            readadc10 SENSOR_RED, l
            k = l * j
            if k <= red_avg or blocked > 0 then
                high LED
                nap 1
                readadc10 SENSOR_RED, k
                low LED
                nap 1
            else
                k = l
                low LED
                low LED
                nap 2
            endif
            readadc10 SENSOR_RED, red
            readadc10 SENSOR_GREEN, green
            readadc10 SENSOR_BLUE, blue

            ; Debug serial output
            ;gosub high_speed
            ;sertxd("0: ", #red, ",", #green, ",", #blue, 13)
            ;gosub low_speed

            ; Accumulate data samples
            red_avg = red + red_avg
            green_avg = green + green_avg
            blue_avg = blue + blue_avg
        endif
        low SENSOR_POWER ; Sensors off

        ; Debug blocked output
        ;gosub high_speed
        ;sertxd(#k, ", ", #l, ", ", #red, 13)
        ;gosub low_speed

        if k > 3 then
            k = k - 3
        else
            k = 0
        endif
        if k > l and k > red then
            flag = FLAG_BLOCKED ; <--- TODO: combine with poss existing flag val
            blocked = 3 ; re-test 3 times after long sequential block
            ; Debug blocked output
            ;gosub high_speed
            ;sertxd("BLOCKED", 13)
            ;gosub low_speed
        else
            if blocked > 0 then
                dec blocked
            endif
        endif

        gosub check_serial_comms
        gosub low_power_and_delay
    next j

    ; Calculate averages
    red_avg = red_avg / SAMPLES_PER_AVERAGE
    green_avg = green_avg / SAMPLES_PER_AVERAGE
    blue_avg = blue_avg / SAMPLES_PER_AVERAGE

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
    hi2cout i, (red_byte, green_byte, blue_byte, extra_byte)

    ; Debug serial output
    ;sertxd(#red_byte, ",", #green_byte, ",", #blue_byte, ",", #extra_byte, 13)

    ; Write current position to micro's eprom and increment
    write 0, WORD i
    i = i + 4

    ; I'm still alive!
    ;high LED
    ;nap 1 ; 72ms
    ;low LED

    goto main

low_power_and_delay:
    ; Save power and sleep
    sleep 2 ; 1 = 2.3sec watchdog timer
    return

check_serial_comms:
    gosub high_speed
    ;disconnect
    sertxd("Hello?")
    serrxd [100, serial_checked], ser_in_byte
    ;serrxd [100, serial_checked], ("cmd"), ser_in_byte
    ;serrxd ser_in_byte

    if ser_in_byte = "a" then
        gosub display_status
        gosub flash_led

    elseif ser_in_byte = "b" then
        ;sertxd("Dumping data and resetting pointer", 13)
        gosub dump_data_and_reset_pointer

    elseif ser_in_byte = "c" then
        ;sertxd("Dumping data", 13)
        gosub dump_data

    elseif ser_in_byte = "d" then
        ;sertxd("Dumping all eprom data", 13)
        gosub dump_all_eprom_data

    elseif ser_in_byte = "e" then
        gosub reset_pointer
        ;sertxd("Pointer reset", 13)

    elseif ser_in_byte = "f" then
        gosub reset_reboot_counter
        ;sertxd("Zero reboot counter", 13)

    elseif ser_in_byte = "g" then
        ;sertxd("Erasing data, reboot counter & pointer", 13)
        gosub erase_all_data
        ;sertxd("Done", 13)

    else
        sertxd("Error ", #ser_in_byte, 13)

    endif

serial_checked:
    ;reconnect
    gosub low_speed
    return

flash_led:
    ; Get some attention
    for k = 1 to 20
        high LED
        nap 1
        low LED
        nap 2 ; 72ms
    next k
    return

display_status:
    read 2, WORD k
    sertxd("Reboot count: ", #k, 13)
    sertxd("Mem pointer: ", #i, 13)
    calibadc10 k
    l = 52378 / k * 2
    sertxd("Batt: ", #l, "0mV", 13)
    return

dump_data_and_reset_pointer:
    ; Output eprom data and reset pointer
    hi2csetup i2cmaster, %10100000, i2cfast_32, i2cword
    read 0, WORD l
    for k = 0 to l step 4
        hi2cin k, (red_byte, green_byte, blue_byte, extra_byte)
        sertxd (red_byte, green_byte, blue_byte, extra_byte)
    next k
    sertxd("eof")
    gosub reset_pointer
    hi2csetup i2cmaster, %10100000, i2cfast, i2cword
    return

dump_data:
    ; Debug output data
    hi2csetup i2cmaster, %10100000, i2cfast_32, i2cword
    read 0, WORD l
    for k = 0 to l step 4
        hi2cin k, (red_byte, green_byte, blue_byte, extra_byte)
        sertxd (red_byte, green_byte, blue_byte, extra_byte)
    next k
    sertxd("eof")
    hi2csetup i2cmaster, %10100000, i2cfast, i2cword
    return

dump_all_eprom_data:
    ; Debug output all eprom data
    hi2csetup i2cmaster, %10100000, i2cfast_32, i2cword
    for k = 0 to 65531 step 4
        hi2cin k, (red_byte, green_byte, blue_byte, extra_byte)
        sertxd (red_byte, green_byte, blue_byte, extra_byte)
    next k
    sertxd("eof")
    hi2csetup i2cmaster, %10100000, i2cfast, i2cword
    return

reset_pointer:
    i = 0 ; reset pointer back to start of mem
    write 0, WORD i
    return

reset_reboot_counter:
    k = 0
    write 2, WORD k ; reset reboot counter back to 0
    return

erase_all_data:
    ; Debug erase eprom data (help with debugging)
    hi2csetup i2cmaster, %10100000, i2cfast_32, i2cword
    for k = 0 to 65534
        hi2cout k, (255)
    next k
    gosub reset_pointer
    gosub reset_reboot_counter
    hi2csetup i2cmaster, %10100000, i2cfast, i2cword
    return

high_speed:
    setfreq m32; k31, k250, k500, m1, m2, m4, m8, m16, m32
    return

low_speed:
    setfreq k500; k31, k250, k500, m1, m2, m4, m8, m16, m32
    return
