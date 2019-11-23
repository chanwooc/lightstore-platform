 
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
## XDC generated for xcvu095-ffva2104-2 device
# 275.0MHz GT Reference clock constraint
create_clock -name GT_REFCLK1_FMC1 -period 3.636	 [get_pins -hier -filter {NAME =~ */fmc1_gt_clk_i/O}]
create_clock -name GT_REFCLK1_FMC2 -period 3.636	 [get_pins -hier -filter {NAME =~ */fmc2_gt_clk_i/O}]

####################### GT reference clock LOC #######################
set_property LOC N9 [get_ports aurora_clk_fmc1_gt_clk_p_v]
set_property LOC N8 [get_ports aurora_clk_fmc1_gt_clk_n_v]
set_property LOC AA9 [get_ports aurora_clk_fmc2_gt_clk_p_v]
set_property LOC AA8 [get_ports aurora_clk_fmc2_gt_clk_n_v]

#create_clock -name auroraI_user_clk_i_fmc1 -period 9.091	 [get_pins -hierarchical -regexp {.*auroraIntra1.*/aurora_module_i/clock_module_i/user_clk_buf_i/O}]
#create_clock -name auroraI_user_clk_i_fmc2 -period 9.091	 [get_pins -hierarchical -regexp {.*auroraIntra2.*/aurora_module_i/clock_module_i/user_clk_buf_i/O}]
create_clock -name auroraI_user_clk_i_fmc1 -period 9.091 [get_pins -hierarchical -regexp {.*flashCtrls_0.*/aurora_module_i/clock_module_i/user_clk_buf_i/O}]
create_clock -name auroraI_user_clk_i_fmc2 -period 9.091 [get_pins -hierarchical -regexp {.*flashCtrls_1.*/aurora_module_i/clock_module_i/user_clk_buf_i/O}]

set pcie250 [get_clocks -of_objects  [get_pins *ep7/pcie_ep/inst/gt_top_i/phy_clk_i/bufg_gt_userclk/O]]
create_generated_clock -name auroraI_init_clk_i -master_clock $pcie250 [get_pins *ep7/clkgen_pll/CLKOUT0]
set portal_usrclk [get_clocks -of_objects [get_pins *ep7/CLK_epPortalClock]]
set auroraI_init_clk_i [get_clocks -of_objects [get_pins *ep7/CLK_epDerivedClock]]

###### CDC async group auroraI_user_clk_i and portal_usrclk ##############
set_clock_groups -asynchronous -group {auroraI_user_clk_i_fmc1} -group $portal_usrclk
set_clock_groups -asynchronous -group {auroraI_user_clk_i_fmc2} -group $portal_usrclk

###### CDC async group auroraI_init_clk_i and portal_usrclk ##############
set_clock_groups -asynchronous -group $auroraI_init_clk_i -group $portal_usrclk

###### CDC in RESET_LOGIC from INIT_CLK to USER_CLK ##############
set_false_path -to [get_pins -hier *aurora_8b10b_fmc1_cdc_to*/D]
set_false_path -to [get_pins -hier *aurora_8b10b_fmc2_cdc_to*/D]

# False path constraints for Ultrascale Clocking Module (BUFG_GT)
# ----------------------------------------------------------------------------------------------------------------------
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *clock_module_i/*PLL_NOT_LOCKED*}]
set_false_path -through [get_pins -hierarchical -filter {NAME =~ *clock_module_i/*user_clk_buf_i/CLR}]
