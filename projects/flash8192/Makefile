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
CPPFILES=main.cpp

BSVPATH += ../../lib \
		   ../../platform/flash_ctrl/common \
		   ../../platform/flash_ctrl/model_main \
		   ../../platform/flash_ctrl/hw_main \

CONNECTALFLAGS += -D DataBusWidth=128 -D IMPORT_HOST_CLOCKS

ip.%:
	make gen.$(*)
	BOARD=$(*) make aurora_intra

.PHONY: aurora_intra

# per-platform definitions
ifeq ($(BOARD), bluesim)
CONNECTALFLAGS += --bscflags " -D BSIM -D NAND_SIM "

else ifeq ($(BOARD), verilator)
CONNECTALFLAGS += --bscflags " -D BSIM -D NAND_SIM "

else ifeq ($(BOARD), zcu102)
NOHOST_XDC = ../../misc/nohost_zcu.xdc

CONNECTALFLAGS += --bscflags " -D LED_AURORA"
PINOUT_FILE=pinout.zcu102.sw.json

# Best Set-up for ZCU102 (2 Masters, 2 ReadEngines and 4 WriteEngines)
NUMBER_OF_MASTERS=2
PLATFORM_NUMBER_OF_MASTERS=2
NUMBER_OF_RENGINES=2 # Flash Write (DMA Read)
NUMBER_OF_WENGINES=4 # Flash Read  (DMA Write)

# Connectal Main Clock: 175 MHz --> realmainclockpreiod=5.714
# Connectal Main Clock: 200 MHz --> realmainclockpreiod=5 (Current)
# Derived clock for Aurora Init Clock (110 MHz, T=9.090) --> real derivedclockpreiod=9.090
CONNECTALFLAGS += -D NumReadClients=$(NUMBER_OF_RENGINES) -D NumWriteClients=$(NUMBER_OF_WENGINES)
CONNECTALFLAGS += --mainclockperiod=5 --derivedclockperiod=9.090
CONNECTALFLAGS += -D DEFAULT_NOPROGRAM=1    # To suppress automatic fpga program
CONNECTALFLAGS += -D ZCU_AXI_SLAVE_START=2  # To bypass HPC0,1
# CONNECTALFLAGS += -D MMU_INDEX_WIDTH=11     # To support larger MMU table (portalAlloc up to 2GB)

CONNECTALFLAGS += \
	--bsvpath ../../platform/aurora_intra/aurora_8b10b_zcu/ \
	--verilog ../../platform/aurora_intra/aurora_8b10b_zcu/ \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_zcu/aurora_8b10b_zcu.xci \
	--constraint ../../platform/aurora_intra/aurora_8b10b_zcu/aurora_8b10b_zcu_exdes.xdc \
	--constraint $(NOHOST_XDC) \
	--implconstraint ../../platform/aurora_intra/aurora_8b10b_zcu/aurora_8b10b_zcu_exdes.xdc \
	--implconstraint $(NOHOST_XDC) 

$(IPDIR)/$(BOARD)/aurora_8b10b_zcu/aurora_8b10b_zcu.xci: ../../coregen/synth-aurora-intra-zcu.tcl
	cd $(BOARD); vivado -mode batch -source ../../../coregen/synth-aurora-intra-zcu.tcl

aurora_intra: $(IPDIR)/$(BOARD)/aurora_8b10b_zcu/aurora_8b10b_zcu.xci

else ifeq ($(BOARD), vc707g2)
NOHOST_XDC = ../../misc/nohost_vc707.xdc

NUMBER_OF_RENGINES=2 # Flash Write (DMA Read)
NUMBER_OF_WENGINES=8 # Flash Read  (DMA Write)
CONNECTALFLAGS += -D NumReadClients=$(NUMBER_OF_RENGINES) -D NumWriteClients=$(NUMBER_OF_WENGINES)

CONNECTALFLAGS += --mainclockperiod=10 --derivedclockperiod=9.090
CONNECTALFLAGS += -D DEFAULT_NOPROGRAM=1    # To suppress automatic fpga program

CONNECTALFLAGS += \
	--bsvpath ../../platform/aurora_intra/aurora_8b10b_vc707/ \
	--verilog ../../platform/aurora_intra/aurora_8b10b_vc707/ \
	--xci $(CONNECTALDIR)/out/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci \
	--constraint ../../platform/aurora_intra/aurora_8b10b_vc707/aurora_8b10b_fmc1_exdes.xdc \
	--constraint $(NOHOST_XDC) \
	--implconstraint ../../platform/aurora_intra/aurora_8b10b_vc707/aurora_8b10b_fmc1_exdes.xdc \
	--implconstraint $(NOHOST_XDC)

$(IPDIR)/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci: ../../coregen/synth-aurora-intra-zcu.tcl
	cd $(BOARD); vivado -mode batch -source ../../../coregen/synth-aurora-intra-vc707-fmc1.tcl

aurora_intra: $(IPDIR)/$(BOARD)/aurora_8b10b_fmc1/aurora_8b10b_fmc1.xci
endif

include $(CONNECTALDIR)/Makefile.connectal
