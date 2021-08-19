BASEDIR=$(abspath ../../)
CONNECTALDIR=$(BASEDIR)/tools/connectal/


# Auto-top variables
MEM_READ_INTERFACES=lMain.dmaReadClient
MEM_WRITE_INTERFACES=lMain.dmaWriteClient
S2H_INTERFACES=AmfRequest:Main.request
H2S_INTERFACES=Main:AmfIndication:host.derivedClock,host.derivedReset
#H2S_INTERFACES=Main:AmfIndication:host

# Pin declaration
PIN_TYPE=Top_Pins
PIN_TYPE_INCLUDE=Top_Pins
AUTOTOP=--interface pins:Main.pins

BSVFILES = Main.bsv

CPPFILES = main.cpp
CPPFILES += $(CONNECTALDIR)/cpp/DmaBuffer.cpp

BSVPATH += $(BASEDIR)/lib \
		   $(BASEDIR)/platform/flash_ctrl/common \
		   $(BASEDIR)/platform/flash_ctrl/model_main \
		   $(BASEDIR)/platform/flash_ctrl/hw_main \
		   $(BASEDIR)/modules/aftl 

#CONNECTALFLAGS += -D DataBusWidth=256 -D IMPORT_HOSTIF -D XILINX_SYS_CLK -D USE_WIDE_WIDTH
CONNECTALFLAGS += -D DataBusWidth=256 -D IMPORT_HOST_CLOCKS -D USE_WIDE_WIDTH
CONNECTALFLAGS += -D TWO_FLASH_CARDS --bscflags " -D TWO_FLASH_CARDS " # two flash cards (bscflags redundant?)
CONNECTALFLAGS += -D DMA_WRITE_PIPELINED # Makes more sense as long as we generate reqs only if burst data is ready

## SLC or MLC
ifdef SLC
CONNECTALFLAGS += -D SLC
endif

# per-platform definitions
ifeq ($(BOARD), $(filter $(BOARD), bluesim verilator))
CONNECTALFLAGS += --bscflags " -D BSIM -D SIM_BRAM -D SIM_DMA_WRITE_LATENCY=1 " #-D SIM_DMA_READ_LATENCY=1 "
CONNECTALFLAGS += --bsvpath $(BASEDIR)/platform/aurora_intra/aurora_8b10b_vcu108  # use vc707 simulation model

else ifeq ($(BOARD), vcu108)
CONNECTALFLAGS += --mainclockperiod=5 --derivedclockperiod=9.090
CONNECTALFLAGS += -D DEFAULT_NOPROGRAM=1    # To suppress automatic fpga program

NOHOST_XDC = $(BASEDIR)/misc/vcu108.xdc
CONNECTALFLAGS += \
	--bsvpath $(BASEDIR)/platform/aurora_intra/aurora_8b10b_vcu108/ \
	--verilog $(BASEDIR)/platform/aurora_intra/aurora_8b10b_vcu108/ \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc0/aurora_8b10b_fmc0.xci \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci \
	--implconstraint $(NOHOST_XDC) \
	--implconstraint $(BASEDIR)/platform/aurora_intra/aurora_8b10b_vcu108/aurora_8b10b_fmcs_exdes.xdc

AURORA_INTRA0=$(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc0/aurora_8b10b_fmc0.xci
AURORA_INTRA1=$(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci
prebuild:: $(AURORA_INTRA0) $(AURORA_INTRA1)

$(AURORA_INTRA0): $(BASEDIR)/coregen/synth-aurora-intra-vcu108-fmc0.tcl
	(cd $(BOARD); vivado -mode batch -source $<)
$(AURORA_INTRA1): $(BASEDIR)/coregen/synth-aurora-intra-vcu108-fmc1.tcl
	(cd $(BOARD); vivado -mode batch -source $<)

else ifeq ($(BOARD), vc707g2)
CONNECTALFLAGS += --mainclockperiod=8 --derivedclockperiod=9.090
CONNECTALFLAGS += -D DEFAULT_NOPROGRAM=1    # To suppress automatic fpga program

NOHOST_XDC = $(BASEDIR)/misc/vc707.xdc
CONNECTALFLAGS += \
	--bsvpath $(BASEDIR)/platform/aurora_intra/aurora_8b10b_vc707/ \
	--verilog $(BASEDIR)/platform/aurora_intra/aurora_8b10b_vc707/ \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc0/aurora_8b10b_fmc0.xci \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci \
	--implconstraint $(NOHOST_XDC) \
	--implconstraint $(BASEDIR)/platform/aurora_intra/aurora_8b10b_vc707/aurora_8b10b_fmcs_exdes.xdc

AURORA_INTRA0=$(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc0/aurora_8b10b_fmc0.xci
AURORA_INTRA1=$(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci
prebuild:: $(AURORA_INTRA0) $(AURORA_INTRA1)

$(AURORA_INTRA0): $(BASEDIR)/coregen/synth-aurora-intra-vc707-fmc0.tcl
	(cd $(BOARD); vivado -mode batch -source $<)
$(AURORA_INTRA1): $(BASEDIR)/coregen/synth-aurora-intra-vc707-fmc1.tcl
	(cd $(BOARD); vivado -mode batch -source $<)
endif

include $(CONNECTALDIR)/Makefile.connectal
