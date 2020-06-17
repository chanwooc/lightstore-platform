CONNECTALDIR=../../tools/connectal/

# Auto-top variables
S2H_INTERFACES=AftlRequest:Main.request
H2S_INTERFACES=Main:AftlIndication
# MEM_READ_INTERFACES=lMain.dmaReadClient
# MEM_WRITE_INTERFACES=lMain.dmaWriteClient

# Pin declaration
# PIN_TYPE=Top_Pins
# PIN_TYPE_INCLUDE=Top_Pins
# AUTOTOP=--interface pins:Main.pins

BSVFILES = Main.bsv
CPPFILES = main.cpp

BSVPATH += ../../lib \
		   ../../platform/flash_ctrl/common \
		   ../../modules/aftl 


CONNECTALFLAGS += -D DataBusWidth=128 -D IMPORT_HOST_CLOCKS
CONNECTALFLAGS += -D FLASH_FMC2 --bscflags " -D FLASH_FMC2 " # two flash cards

# NUMBER_OF_RENGINES=2 
# NUMBER_OF_WENGINES=2 
# CONNECTALFLAGS += -D NumReadClients=$(NUMBER_OF_RENGINES) -D NumWriteClients=$(NUMBER_OF_WENGINES) 


# per-platform definitions
ifeq ($(BOARD), bluesim)
#CONNECTALFLAGS += --bscflags " -D BSIM -D NAND_SIM "
CONNECTALFLAGS += --bscflags " -D SIM_BRAM "

else ifeq ($(BOARD), verilator)
#CONNECTALFLAGS += --bscflags " -D BSIM -D NAND_SIM "
CONNECTALFLAGS += --bscflags " -D SIM_BRAM "

else ifeq ($(BOARD), vcu108)
CONNECTALFLAGS += --mainclockperiod=5
CONNECTALFLAGS += -D DEFAULT_NOPROGRAM=1    # To suppress automatic fpga program

NOHOST_XDC = ../../misc/vcu108.xdc
CONNECTALFLAGS += \
	--constraint $(NOHOST_XDC) \
	--implconstraint $(NOHOST_XDC)

else ifeq ($(BOARD), vc707g2)
CONNECTALFLAGS += --mainclockperiod=7
CONNECTALFLAGS += -D DEFAULT_NOPROGRAM=1    # To suppress automatic fpga program

NOHOST_XDC = ../../misc/vc707.xdc
CONNECTALFLAGS += \
	--constraint $(NOHOST_XDC) \
	--implconstraint $(NOHOST_XDC)
endif

include $(CONNECTALDIR)/Makefile.connectal
