`include "ConnectalProjectConfig.bsv"
import ControllerTypes::*;

`ifdef TWO_FLASH_CARDS
typedef 2 NUM_CARDS;
`else
typedef 1 NUM_CARDS;
`endif

typedef struct {
	Bit#(1) card;
	FlashCmd fcmd;
} DualFlashCmd deriving (Bits, Eq, FShow);
