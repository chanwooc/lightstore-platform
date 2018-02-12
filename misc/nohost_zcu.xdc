#CDC for auroraIntra clocks
#set_clock_groups -asynchronous -group [get_clocks auroraI_init_clk_i] -group [get_clocks auroraI_user_clk_i]
#set_clock_groups -asynchronous -group [get_clocks GT_REFCLK1] -group {auroraI_init_clk_i auroraI_user_clk_i}

#CDC from auroraIntra clocks to/from clk_fpga_0 (usually 200MHz Clock)
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks clk_pl_0] -group [get_clocks -include_generated_clocks GT_REFCLK1]
