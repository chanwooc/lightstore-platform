CONNECTALDIR=../../tools/connectal/

# Auto-top variables
S2H_INTERFACES=FlashRequest:Main.request
H2S_INTERFACES=Main:FlashIndication:host.derivedClock,host.derivedReset
MEM_READ_INTERFACES=lMain.dmaReadClient
MEM_WRITE_INTERFACES=lMain.dmaWriteClient

# Pin declaration
PIN_TYPE=Top_Pins
PIN_TYPE_INCLUDE=Top_Pins
AUTOTOP=--interface pins:Main.pins

BSVFILES = Main.bsv
CPPFILES = main.cpp

BSVPATH += ../../lib \
		   ../../platform/flash_ctrl/common \
		   ../../platform/flash_ctrl/model_main \
		   ../../platform/flash_ctrl/hw_main \

CONNECTALFLAGS += -D DataBusWidth=128 -D IMPORT_HOST_CLOCKS
#CONNECTALFLAGS += -D DMA_WRITE_PIPELINED # This option only works with DMA-length=128 (Not on 8192) for WE=1
CONNECTALFLAGS += -D FLASH_FMC2 --bscflags " -D FLASH_FMC2 " # two flash cards

NUMBER_OF_RENGINES=2 # Flash Write (DMA Read)
NUMBER_OF_WENGINES=2 # Flash Read  (DMA Write) # Needs a MemWriteEngine Patch
CONNECTALFLAGS += -D NumReadClients=$(NUMBER_OF_RENGINES) -D NumWriteClients=$(NUMBER_OF_WENGINES) # --bscflags " -D NumWriteEngines=$(NUMBER_OF_WENGINES) "

ip.%:
	make gen.$(*)
	BOARD=$(*) make aurora_intra

.PHONY: aurora_intra

# per-platform definitions
ifeq ($(BOARD), bluesim)
CONNECTALFLAGS += --bscflags " -D BSIM -D NAND_SIM "
CONNECTALFLAGS += --bsvpath ../../platform/aurora_intra/aurora_8b10b_vc707  # use vc707 simulation model

else ifeq ($(BOARD), verilator)
CONNECTALFLAGS += --bscflags " -D BSIM -D NAND_SIM "
CONNECTALFLAGS += --bsvpath ../../platform/aurora_intra/aurora_8b10b_vc707

else ifeq ($(BOARD), vcu108)
CONNECTALFLAGS += --mainclockperiod=6 --derivedclockperiod=9.090
CONNECTALFLAGS += -D DEFAULT_NOPROGRAM=1    # To suppress automatic fpga program

NOHOST_XDC = ../../misc/nohost_vcu108.xdc
CONNECTALFLAGS += \
	--bsvpath ../../platform/aurora_intra/aurora_8b10b_vcu108/ \
	--verilog ../../platform/aurora_intra/aurora_8b10b_vcu108/ \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2.xci \
	--constraint ../../platform/aurora_intra/aurora_8b10b_vcu108/aurora_8b10b_fmcs_exdes.xdc \
	--constraint $(NOHOST_XDC) \
	--implconstraint ../../platform/aurora_intra/aurora_8b10b_vcu108/aurora_8b10b_fmcs_exdes.xdc \
	--implconstraint $(NOHOST_XDC)

AURORA_INTRA1=$(IPDIR)/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci
AURORA_INTRA2=$(IPDIR)/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2.xci

$(AURORA_INTRA1): ../../coregen/synth-aurora-intra-vcu108-fmc1.tcl
	cd $(BOARD); vivado -mode batch -source ../../../coregen/synth-aurora-intra-vcu108-fmc1.tcl
$(AURORA_INTRA2): ../../coregen/synth-aurora-intra-vcu108-fmc2.tcl
	cd $(BOARD); vivado -mode batch -source ../../../coregen/synth-aurora-intra-vcu108-fmc2.tcl

aurora_intra: $(AURORA_INTRA1) $(AURORA_INTRA2)

else ifeq ($(BOARD), vc707g2)
CONNECTALFLAGS += --mainclockperiod=7 --derivedclockperiod=9.090
CONNECTALFLAGS += -D DEFAULT_NOPROGRAM=1    # To suppress automatic fpga program

NOHOST_XDC = ../../misc/nohost_vc707.xdc
CONNECTALFLAGS += \
	--bsvpath ../../platform/aurora_intra/aurora_8b10b_vc707/ \
	--verilog ../../platform/aurora_intra/aurora_8b10b_vc707/ \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2.xci \
	--constraint ../../platform/aurora_intra/aurora_8b10b_vc707/aurora_8b10b_fmcs_exdes.xdc \
	--constraint $(NOHOST_XDC) \
	--implconstraint ../../platform/aurora_intra/aurora_8b10b_vc707/aurora_8b10b_fmcs_exdes.xdc \
	--implconstraint $(NOHOST_XDC)

AURORA_INTRA1=$(IPDIR)/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci
AURORA_INTRA2=$(IPDIR)/$(BOARD)/aurora_8b10b_fmc2/aurora_8b10b_fmc2.xci

$(AURORA_INTRA1): ../../coregen/synth-aurora-intra-vc707-fmc1.tcl
	cd $(BOARD); vivado -mode batch -source ../../../coregen/synth-aurora-intra-vc707-fmc1.tcl
$(AURORA_INTRA2): ../../coregen/synth-aurora-intra-vc707-fmc2.tcl
	cd $(BOARD); vivado -mode batch -source ../../../coregen/synth-aurora-intra-vc707-fmc2.tcl

aurora_intra: $(AURORA_INTRA1) $(AURORA_INTRA2)
endif

include $(CONNECTALDIR)/Makefile.connectal
