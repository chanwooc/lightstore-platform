import ControllerTypes::*;

typedef struct {
	Bit#(1) card;
	FlashCmd fcmd;
} MultiFlashCmd deriving (Bits, Eq, FShow);
