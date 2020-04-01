import ControllerTypes::*;

`ifdef FLASH_FMC2
typedef 2 NUM_CARDS;
`else
typedef 1 NUM_CARDS;
`endif

typedef struct {
	Bit#(1) card;
	FlashCmd fcmd;
} MultiFlashCmd deriving (Bits, Eq, FShow);
