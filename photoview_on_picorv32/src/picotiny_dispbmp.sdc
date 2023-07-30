//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.8.09 Education
//Created Time: 2023-04-18 21:19:52
create_clock -name psramclk -period 6.304 -waveform {0 3.152} [get_pins {upll_psram_memclk/rpll_inst/CLKOUT}]
create_clock -name clkout_371p25m -period 2.694 -waveform {0 1.347} [get_pins {u_Gowin_rPLL_HDMI/rpll_inst/CLKOUT}]
create_generated_clock -name clkout_37p125m -source [get_pins {u_Gowin_CLKDIV5/clkdiv_inst/CLKOUT}] -master_clock clkout_74p25m -divide_by 2 [get_pins {u_Gowin_CLKDIV2/clkdiv_inst/CLKOUT}]
create_generated_clock -name clkout_74p25m -source [get_pins {u_Gowin_rPLL_HDMI/rpll_inst/CLKOUT}] -master_clock clkout_371p25m -divide_by 5 [get_pins {u_Gowin_CLKDIV5/clkdiv_inst/CLKOUT}]
