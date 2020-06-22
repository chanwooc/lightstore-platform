BASEDIR=$(abspath ../../)
CONNECTALDIR=$(BASEDIR)/tools/connectal/

S2H_INTERFACES = Ddr4PerfRequest:Ddr4Perf.request
H2S_INTERFACES = Ddr4Perf:Ddr4PerfIndication:host

PIN_TYPE = Top_Pins
PIN_TYPE_INCLUDE = Ddr4Perf
AUTOTOP = --interface pins:Ddr4Perf.pins

# DDR4 IP location
MIGDIR=$(abspath ../../platform/ddr4/)

CPPFILES = testddr4.cpp
BSVFILES = Ddr4Perf.bsv
BSVPATH += $(BASEDIR)/lib \
		   $(MIGDIR)

CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK

ifeq ($(BOARD), $(filter $(BOARD), vcu108 vcu118))

# below are for ddr4_v2_0
CONNECTALFLAGS += \
	--verilog $(MIGDIR)/ddr4_wrapper.v \
	--xci $(CONNECTALDIR)/out/$(BOARD)/ddr4_0/ddr4_0.xci

ifeq ($(BOARD), vcu108)
CONNECTALFLAGS += --implconstraint $(MIGDIR)/ddr4_vcu108.xdc
else
CONNECTALFLAGS += --implconstraint $(MIGDIR)/ddr4_vcu118.xdc
endif

DDR4_V = $(CONNECTALDIR)/out/$(BOARD)/ddr4_0/ddr4_0_stub.v

SYNCFIFO_748_32 = $(CONNECTALDIR)/out/$(BOARD)/sync_bram_fifo_w748_d32/sync_bram_fifo_w748_d32.xci
SYNCFIFO_640_32 = $(CONNECTALDIR)/out/$(BOARD)/sync_bram_fifo_w640_d32/sync_bram_fifo_w640_d32.xci

CONNECTALFLAGS += \
	--xci $(SYNCFIFO_748_32) \
	--xci $(SYNCFIFO_640_32)

prebuild:: $(DDR4_V) $(SYNCFIFO_748_32) $(SYNCFIFO_640_32)

$(DDR4_V): $(BASEDIR)/coregen/synth-ddr4.tcl
	(cd $(BOARD); vivado -mode batch -source $^)

$(SYNCFIFO_748_32): $(BASEDIR)/coregen/synth-sync-bram-fifo.tcl
	(cd $(PROJECTDIR); vivado -mode batch -source $^ -tclargs 748 32)

$(SYNCFIFO_640_32): $(BASEDIR)/coregen/synth-sync-bram-fifo.tcl
	(cd $(PROJECTDIR); vivado -mode batch -source $^ -tclargs 640 32)

endif

include $(CONNECTALDIR)/Makefile.connectal
