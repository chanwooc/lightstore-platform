source "board.tcl"
source "$connectaldir/scripts/connectal-synth-ip.tcl"

if {$boardname == {vcu108}} {
    connectal_synth_ip ddr4 2.2 ddr4_0 [list CONFIG.C0_CLOCK_BOARD_INTERFACE {Custom} CONFIG.C0.DDR4_InputClockPeriod {3332} CONFIG.C0.DDR4_MemoryPart {EDY4016AABG-DR-F} CONFIG.C0.DDR4_DataWidth {80} CONFIG.C0.BANK_GROUP_WIDTH {1} CONFIG.System_Clock {No_Buffer} CONFIG.Debug_Signal {Disable}]
}

if {$boardname == {vcu118}} {
    connectal_synth_ip ddr4 2.2 ddr4_0 [list CONFIG.C0_CLOCK_BOARD_INTERFACE {Custom} CONFIG.C0.DDR4_TimePeriod {833} CONFIG.C0.DDR4_InputClockPeriod {4000} CONFIG.C0.DDR4_MemoryPart {MT40A256M16GE-083E} CONFIG.C0.DDR4_DataWidth {80} CONFIG.C0.BANK_GROUP_WIDTH {1} CONFIG.System_Clock {No_Buffer} CONFIG.Debug_Signal {Disable}]
}
