 
################################################################################
##
## (c) Copyright 2010-2014 Xilinx, Inc. All rights reserved.
##
## This file contains confidential and proprietary information
## of Xilinx, Inc. and is protected under U.S. and
## international copyright and other intellectual property
## laws.
##
## DISCLAIMER
## This disclaimer is not a license and does not grant any
## rights to the materials distributed herewith. Except as
## otherwise provided in a valid license issued to you by
## Xilinx, and to the maximum extent permitted by applicable
## law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
## WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
## AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
## BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
## INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
## (2) Xilinx shall not be liable (whether in contract or tort,
## including negligence, or under any other theory of
## liability) for any loss or damage of any kind or nature
## related to, arising under or in connection with these
## materials, including for any direct, or any indirect,
## special, incidental, or consequential loss or damage
## (including loss of data, profits, goodwill, or any type of
## loss or damage suffered as a result of any action brought
## by a third party) even if such damage or loss was
## reasonably foreseeable or Xilinx had been advised of the
## possibility of the same.
##
## CRITICAL APPLICATIONS
## Xilinx products are not designed or intended to be fail-
## safe, or for use in any application requiring fail-safe
## performance, such as life-support or safety devices or
## systems, Class III medical devices, nuclear facilities,
## applications related to the deployment of airbags, or any
## other applications that could lead to death, personal
## injury, or severe property or environmental damage
## (individually and collectively, "Critical
## Applications"). Customer assumes the sole risk and
## liability of any use of Xilinx products in Critical
## Applications, subject only to applicable laws and
## regulations governing limitations on product liability.
##
## THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
## PART OF THIS FILE AT ALL TIMES.
##
##
################################################################################
## XDC generated for xc7vx485t-ffg1761-2 device
# 275.0MHz GT Reference clock constraint
create_clock -name GT_REFCLK1 -period 3.636	 [get_pins -hier -regexp {.*/fmc1_gt_clk_i/O}]

####################### GT reference clock LOC #######################
set_property LOC E9 [get_ports aurora_clk_fmc1_gt_clk_n_v]
set_property LOC E10 [get_ports aurora_clk_fmc1_gt_clk_p_v]

create_clock -name auroraI_user_clk_i -period 9.091	 [get_pins -hierarchical -regexp {.*/aurora_module_i/clock_module_i/user_clk_buf_i/O}]

set portal_usrclk [get_clocks {clkgen_pll_CLKOUT1}]
set auroraI_init_clk_i [get_clocks {clkgen_pll_CLKOUT0}]

###### CDC async group auroraI_user_clk_i and portal_usrclk ##############
# set_clock_groups -asynchronous -group {auroraI_user_clk_i} -group $portal_usrclk

set_max_delay -from $auroraI_init_clk_i -to $portal_usrclk -datapath_only [get_property PERIOD $portal_usrclk]
set_max_delay -from $portal_usrclk -to $auroraI_init_clk_i -datapath_only [get_property PERIOD $portal_usrclk]

####### CDC async group auroraI_init_clk_i and portal_usrclk ##############
# set_clock_groups -asynchronous -group $auroraI_init_clk_i -group $portal_usrclk

set_max_delay -from {auroraI_user_clk_i} -to $portal_usrclk -datapath_only [get_property PERIOD $portal_usrclk]
set_max_delay -from $portal_usrclk -to {auroraI_user_clk_i} -datapath_only [get_property PERIOD $portal_usrclk]

###### CDC in RESET_LOGIC from INIT_CLK to USER_CLK ##############
# set_clock_groups -asynchronous -group $auroraI_init_clk_i -group {auroraI_user_clk_i}
set_false_path -to [get_pins -hier *cdc_to*/D]
set_max_delay -from $auroraI_init_clk_i -to [get_clocks auroraI_user_clk_i] -datapath_only 9.091 


###################### Locatoin constrain #########################
#set_property LOC AJ32 [get_ports INIT_CLK_P]
#set_property LOC AK32 [get_ports INIT_CLK_N]
#set_property LOC AV39 [get_ports RESET]
#set_property LOC AW40 [get_ports GT_RESET_IN]
#set_property LOC AR37 [get_ports CHANNEL_UP]
#set_property LOC AT37 [get_ports LANE_UP[0]]
#set_property LOC AM39 [get_ports LANE_UP[1]]
#set_property LOC AN39 [get_ports LANE_UP[2]]
#set_property LOC AP40 [get_ports LANE_UP[3]]
#set_property LOC G28 [get_ports HARD_ERR]   
#set_property LOC G23 [get_ports SOFT_ERR]   
#set_property LOC H23 [get_ports ERR_COUNT[0]]   
#set_property LOC G27 [get_ports ERR_COUNT[1]]   
#set_property LOC G26 [get_ports ERR_COUNT[2]]   
#set_property LOC G22 [get_ports ERR_COUNT[3]]   
#set_property LOC G21 [get_ports ERR_COUNT[4]]   
#set_property LOC H26 [get_ports ERR_COUNT[5]]   
#set_property LOC H25 [get_ports ERR_COUNT[6]]   
#set_property LOC H21 [get_ports ERR_COUNT[7]]   
#   
# 
#set_property LOC M32 [get_ports DRP_CLK_IN]
##// DRP CLK needs a clock LOC
#    
#set_property IOSTANDARD LVDS [get_ports INIT_CLK_P]
#set_property IOSTANDARD LVDS [get_ports INIT_CLK_N]
#set_property IOSTANDARD LVCMOS18 [get_ports RESET]
#set_property IOSTANDARD LVCMOS18 [get_ports GT_RESET_IN]
#set_property IOSTANDARD LVCMOS18 [get_ports CHANNEL_UP]
#set_property IOSTANDARD LVCMOS18 [get_ports LANE_UP[0]]
#set_property IOSTANDARD LVCMOS18 [get_ports LANE_UP[1]]
#set_property IOSTANDARD LVCMOS18 [get_ports LANE_UP[2]]
#set_property IOSTANDARD LVCMOS18 [get_ports LANE_UP[3]]
#set_property IOSTANDARD LVCMOS18 [get_ports HARD_ERR]   
#set_property IOSTANDARD LVCMOS18 [get_ports SOFT_ERR]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[0]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[1]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[2]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[3]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[4]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[5]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[6]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[7]]   
#    
#    
#set_property IOSTANDARD SSTL15 [get_ports DRP_CLK_IN]
##// DRP CLK needs a clock IOSTDLOC
#    
###################################################################


############################### GT LOC ###################################
set_property LOC GTXE2_CHANNEL_X1Y20 [get_cells -hierarchical -regexp {.*aurora_8b10b_fmc1_i/inst/gt_wrapper_i/aurora_8b10b_fmc1_multi_gt_i/gt0_aurora_8b10b_fmc1_i/gtxe2_i}]
set_property LOC GTXE2_CHANNEL_X1Y21 [get_cells -hierarchical -regexp {.*aurora_8b10b_fmc1_i/inst/gt_wrapper_i/aurora_8b10b_fmc1_multi_gt_i/gt1_aurora_8b10b_fmc1_i/gtxe2_i}]
set_property LOC GTXE2_CHANNEL_X1Y22 [get_cells -hierarchical -regexp {.*aurora_8b10b_fmc1_i/inst/gt_wrapper_i/aurora_8b10b_fmc1_multi_gt_i/gt2_aurora_8b10b_fmc1_i/gtxe2_i}]
set_property LOC GTXE2_CHANNEL_X1Y23 [get_cells -hierarchical -regexp {.*aurora_8b10b_fmc1_i/inst/gt_wrapper_i/aurora_8b10b_fmc1_multi_gt_i/gt3_aurora_8b10b_fmc1_i/gtxe2_i}]
  
 # X1Y20
 set_property LOC J2 [get_ports { aurora_fmc1_TXP[3] }]
 set_property LOC J1 [get_ports { aurora_fmc1_TXN[3] }]
 set_property LOC H8 [get_ports { aurora_fmc1_RXP[3] }]
 set_property LOC H7 [get_ports { aurora_fmc1_RXN[3] }]
  # X1Y21
 set_property LOC H4 [get_ports { aurora_fmc1_TXP[2] }]
 set_property LOC H3 [get_ports { aurora_fmc1_TXN[2] }]
 set_property LOC G6 [get_ports { aurora_fmc1_RXP[2] }]
 set_property LOC G5 [get_ports { aurora_fmc1_RXN[2] }]
  # X1Y22
 set_property LOC G2 [get_ports { aurora_fmc1_TXP[1] }]
 set_property LOC G1 [get_ports { aurora_fmc1_TXN[1] }]
 set_property LOC F8 [get_ports { aurora_fmc1_RXP[1] }]
 set_property LOC F7 [get_ports { aurora_fmc1_RXN[1] }]
  # X1Y23
 set_property LOC F4 [get_ports { aurora_fmc1_TXP[0] }]
 set_property LOC F3 [get_ports { aurora_fmc1_TXN[0] }]
 set_property LOC E6 [get_ports { aurora_fmc1_RXP[0] }]
 set_property LOC E5 [get_ports { aurora_fmc1_RXN[0] }]


