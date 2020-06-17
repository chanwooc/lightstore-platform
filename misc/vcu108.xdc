create_generated_clock -name pcie250_userclk [get_pins -hier -regexp .*ep7/pcie_ep/inst/gt_top_i/phy_clk_i/bufg_gt_userclk/O]
create_generated_clock -name portal_main_clk [get_pins -hier -regexp .*ep7/clkgen_pll/CLKOUT1]
create_generated_clock -name portal_derived_clk [get_pins -hier -regexp .*ep7/clkgen_pll/CLKOUT0]

set_clock_groups -asynchronous -group {pcie250_userclk} -group {portal_main_clk}
set_clock_groups -asynchronous -group {pcie250_userclk} -group {portal_derived_clk}
# set_clock_groups -asynchronous -group {portal_derived_clk} -group {portal_main_clk}

# CDC Reset signals (mkSyncReset)
set_false_path -to [get_pins -hier *reset_meta_reg*/D]
