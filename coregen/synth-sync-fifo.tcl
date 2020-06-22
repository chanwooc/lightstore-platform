source board.tcl
source $connectaldir/scripts/connectal-synth-ip.tcl

if {$::argc != 2} {
    error "Usage: $::argv0 WIDTH $::argv1 DEPTH"
} else {
    set ip_width [lindex $argv 0]
    set ip_depth [lindex $argv 1]
}
puts "Sync FIFO Width: $ip_width"
puts "Sync FIFO Depth: $ip_depth"


set sync_fifo_version {13.0}
if {[version -short] >= "2016.4"} {
    set sync_fifo_version {13.1}
}
if {[version -short] >= "2017.4"} {
    set sync_fifo_version {13.2}
}

connectal_synth_ip fifo_generator $sync_fifo_version sync_fifo_w${ip_width}_d${ip_depth} \
    [list \
         CONFIG.Fifo_Implementation {Independent_Clocks_Distributed_RAM} \
         CONFIG.Performance_Options {First_Word_Fall_Through} \
         CONFIG.Input_Data_Width $ip_width \
         CONFIG.Input_Depth $ip_depth \
         CONFIG.Output_Data_Width $ip_width \
         CONFIG.Output_Depth $ip_depth \
         CONFIG.Reset_Pin {false}]
