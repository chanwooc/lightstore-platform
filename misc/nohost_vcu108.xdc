#create_generated_clock -name pcie250 -source [get_pins *ep7/pcie_ep/inst/gt_top_i/phy_clk_i/bufg_gt_userclk/I] -divide_by 2 [get_pins *ep7/pcie_ep/inst/gt_top_i/phy_clk_i/bufg_gt_userclk/O]

#create_generated_clock -name portal_usrclk -source [get_pins *ep7/clkgen_pll/CLKIN1] -multiply_by 4 -divide_by 8 [get_pins *ep7/clkgen_pll/CLKOUT0]

#create_generated_clock -name portal_usrclk -master_clock [get_clocks pcie250] [get_pins *ep7/clkgen_pll/CLKOUT1]

set pcie250 [get_clocks -of_objects  [get_pins *ep7/pcie_ep/inst/gt_top_i/phy_clk_i/bufg_gt_userclk/O]]
set portal_usrclk [get_clocks -of_objects [get_pins *ep7/CLK_epPortalClock]]
set portal_derclk [get_clocks -of_objects [get_pins *ep7/CLK_epDerivedClock]]

set_clock_groups -asynchronous -group $pcie250 -group $portal_usrclk
set_clock_groups -asynchronous -group $pcie250 -group $portal_derclk

#create_generated_clock -name portal_derived -source [get_pins *ep7/clkgen_pll/CLKIN1] -multiply_by 4 -divide_by 9.091 [get_pins *ep7/clkgen_pll/CLKOUT1]



#set_max_delay -from $pcie250 -to  $portal_usrclk [get_property PERIOD $pcie250] -datapath_only

#set_max_delay -to $pcie250 -from  $portal_usrclk [get_property PERIOD $pcie250] -datapath_only


