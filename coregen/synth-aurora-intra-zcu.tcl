source board.tcl
source $connectaldir/scripts/connectal-synth-ip.tcl


set core_version "11.0"
if {[version -short] >= "2017.1"} {
    set core_version "11.1"
}

connectal_synth_ip aurora_8b10b $core_version aurora_8b10b_zcu [list CONFIG.C_AURORA_LANES {4} CONFIG.C_LANE_WIDTH {4} CONFIG.C_LINE_RATE {4.4} CONFIG.C_REFCLK_FREQUENCY {275} CONFIG.C_INIT_CLK {110} CONFIG.Interface_Mode {Streaming} CONFIG.C_UCOLUMN_USED {right} CONFIG.C_START_QUAD {Quad_X1Y1} CONFIG.C_GT_LOC_4 {4} CONFIG.C_GT_LOC_3 {3} CONFIG.C_GT_LOC_2 {2} CONFIG.C_START_LANE {X1Y4} CONFIG.C_REFCLK_SOURCE {MGTREFCLK0 of Quad X1Y1} CONFIG.CHANNEL_ENABLE {X1Y4 X1Y5 X1Y6 X1Y7}]
