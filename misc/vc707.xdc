# set pcie125 [get_clocks -of_objects [get_pins *ep7/pcie_ep/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/mmcm_i/CLKOUT0]]
# set pcie250 [get_clocks -of_objects [get_pins *ep7/pcie_ep/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/mmcm_i/CLKOUT1]]
# 
# set connectal_main [get_clocks -of_objects [get_pins *ep7/clkgen_pll/CLKOUT1]];
# set connectal_derv [get_clocks -of_objects [get_pins *ep7/clkgen_pll/CLKOUT0]];
# 
# set_clock_groups -asynchronous -group $pcie125 -group $connectal_main
# set_clock_groups -asynchronous -group $pcie250 -group $connectal_main
# set_clock_groups -asynchronous -group $pcie125 -group $connectal_derv
# set_clock_groups -asynchronous -group $pcie250 -group $connectal_derv
