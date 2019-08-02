CONNECTALDIR=../../tools/connectal/

# Auto-top variables
S2H_INTERFACES=KtRequest:Main.request
H2S_INTERFACES=Main:KtIndication:host.derivedClock,host.derivedReset
MEM_READ_INTERFACES=lMain.dmaReadClient
MEM_WRITE_INTERFACES=lMain.dmaWriteClient

# Pin declaration
PIN_TYPE=Empty

# Best Set-up for ZCU102 (2 Masters, 2 ReadEngines and 4 WriteEngines)
NUMBER_OF_MASTERS=2
PLATFORM_NUMBER_OF_MASTERS=2
NUMBER_OF_RENGINES=2 # Flash Write (DMA Read)
NUMBER_OF_WENGINES=4 # Flash Read  (DMA Write)

# Connectal Main Clock: 175 MHz: 5.714
# Derived clock for Aurora Init Clock (110 MHz, T=9.090)
CONNECTALFLAGS += -D DataBusWidth=128
CONNECTALFLAGS += -D NumReadClients=$(NUMBER_OF_RENGINES) -D NumWriteClients=$(NUMBER_OF_WENGINES)
CONNECTALFLAGS += -D IMPORT_HOST_CLOCKS
CONNECTALFLAGS += --mainclockperiod=5.714 --derivedclockperiod=9.090
CONNECTALFLAGS += -D ZCU_AXI_SLAVE_START=2  # To bypass HPC0,1
CONNECTALFLAGS += -D DEFAULT_NOPROGRAM=1    # To suppress automatic fpga program
CONNECTALFLAGS += -D MMU_INDEX_WIDTH=13     # To support larger MMU table (portalAlloc up to 8GB)

BSVFILES = Main.bsv \
	../../modules/keytable_merger/KeytableMerger.bsv \
	../../platform/flash_ctrl/common/FlashBusModel.bsv

CPPFILES=main.cpp

ifeq ($(BOARD), bluesim)
CONNECTALFLAGS += -D BSIM
else ifeq ($(BOARD), verilator)
CONNECTALFLAGS += -D BSIM
else
NOHOST_XDC = ../../misc/nohost_zcu.xdc
CONNECTALFLAGS += --constraint $(NOHOST_XDC) \
				  --implconstraint $(NOHOST_XDC)
endif

include $(CONNECTALDIR)/Makefile.connectal
