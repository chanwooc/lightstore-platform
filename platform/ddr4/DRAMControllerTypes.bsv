import ClientServer::*;
import Connectable::*;

// VCU108 & 118 DDR4 IP User Ifc (per DRAM)
//  28-bit addr: low 3-bit ignored (steps of 8)
//    -> This is 80-bit word address
//  640-bit data
//    -> burst of 8 words
//  
// Size of DRAM:
//   80B * 2^28 / 8 = 2.5 GiB
typedef Bit#(28) DDR4UserAddr;
typedef Bit#(640) DDR4UserData;
typedef Bit#(80) DDR4UserWBE;

// DDRRequest
// Used for both reads and writes.
// To perform a read:
//  writeen should be 0
//  address contains the address to read from
//  datain is ignored.
// To perform a write:
//  writeen should be non-zero 80-bit mask
typedef struct {
	// writeen: Enable writing.
	// Set the ith bit of writeen to 1 to write the ith byte of datain to the
	// ith byte of data at the given address.
	// If writeen is 0, this is a read request, and a response is returned.
	// If writeen is not 0, this is a write request, and no response is
	// returned.
	DDR4UserWBE writeen;

	// Address to read to or write from.
	// The DDR4 is 80-bit word addressed (16x5 chips), but each access is a burst of eight 80-bit words
	//  -> single access burst = 640 bit = 80 Byte
	// The address should always be a multiple of 8 (bottom 3 bits 0),
	// otherwise strange things will happen.
	//  E.g., address = 0 -> First 640-bit burst, address = 8 -> Second 640-bit burst
	DDR4UserAddr address;

	// Data to write.
	// For read requests this is ignored.
	// Only those bytes with corresponding bit set in writeen will be written.
	DDR4UserData datain;
} DDR4UserRequest deriving(Bits, Eq, FShow);

typedef Client#(DDR4UserRequest, DDR4UserData) DDR4Client;
typedef Server#(DDR4UserRequest, DDR4UserData) DDR4Server;
