# CDC from auroraIntra clocks to/from clk_fpga_0 (usually 200MHz Clock)
# set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks clk_pl_0] -group [get_clocks -include_generated_clocks GT_REFCLK1]
