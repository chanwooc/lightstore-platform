import ControllerTypes::*;
import DualFlashTypes::*;


// ** LPA Structure **
//   Virtual Block # format:
//      [ Chip # lower N-bit ][ Bus # ][ Card # ]
//
//   Segment # format:
//      [ LPA MSBits ... ][ Chip # upper (K-N)-bit ]
//      where K is number of total bits needed to encode chip #
//            N is number of lower bits used to encode virtual block #
//      Total number of segments: (Number of Physical Block per Chip) * 2^(K-N)
//
//   LPA fields:
//      [ segment # ][ page # ][ virt blk # ]
//      Length: Sum of bits required to encode Card / Bus / Chip / Blk / Page
//
// Types 
// 1. Define "N"  (K is log(ChipsPerBus) from ControllerTypes.bsv)
// 2. LPA component Bit-Width (TSz) and Bit Type (T)

`ifdef BSIM
typedef 3 ChipBitsInVirtBlk; // N = K = 3 (8 chips/bus & all 3bits for virtBlk)
`elsif SLC
typedef 2 ChipBitsInVirtBlk; // N = K = 2 (4 chips/bus & all 2bits for virtBlk)
`else
typedef 3 ChipBitsInVirtBlk; // N = K = 3 (8 chips/bus & all 3bits for virtBlk)
`endif

typedef TMul#(BlocksPerCE, TExp#(TSub#(TLog#(ChipsPerBus), ChipBitsInVirtBlk))) NumSegments;
typedef TMul#(TExp#(ChipBitsInVirtBlk), TMul#(NUM_BUSES, NUM_CARDS)) VirtBlksPerSegment;

typedef TLog#(VirtBlksPerSegment) VirtBlkTSz;
typedef TLog#(PagesPerBlock) PageTSz;
typedef TLog#(NumSegments) SegmentTSz;

typedef Bit#(VirtBlkTSz) VirtBlkT;
typedef Bit#(PageTSz) PageT;
typedef Bit#(SegmentTSz) SegmentT;
typedef Bit#(TAdd#(VirtBlkTSz, TAdd#(PageTSz, SegmentTSz))) LPA;

// type for flash block
typedef TLog#(BlocksPerCE) BlockTSz;
typedef Bit#(BlockTSz) BlockT;

function VirtBlkT getVirtBlkT(LPA lpa);
	return truncate( lpa );
endfunction

function PageT getPageT(LPA lpa);
	return truncate( lpa >> valueOf(VirtBlkTSz) );
endfunction

function SegmentT getSegmentT(LPA lpa);
	return truncate( lpa >> valueOf(TAdd#(PageTSz, VirtBlkTSz)) );
endfunction

// ** Mapping Table **
//   input: {Segment #, Virt Blk #}
//   output: MapEntry{ 2-bit MapStatus, 14-bit Mapped Physical Block # }

`ifndef SIM_BRAM
// DRAM FFFF
// BRAM 0000
typedef enum { NOT_ALLOCATED, ALLOCATED, DEAD } MapStatus deriving (Bits, Eq);
`else
// For testing. At BSIM, RAM is initialized to AAAAAAA
typedef enum { DEAD, ALLOCATED, NOT_ALLOCATED } MapStatus deriving (Bits, Eq);
`endif

typedef struct {
	MapStatus status; // FIXME: DEAD not used
	Bit#(TSub#(16, SizeOf#(MapStatus))) block; // physical block#
} MapEntry deriving (Bits, Eq); // 16-bit (2-bytes) mapping entry

typedef Bit#(TAdd#(SegmentTSz, VirtBlkTSz)) BlockMapAddr;


// ** Physical Block Information Table **
//   input: Physical {Card, Bus, Chip, Block}
//   output: BlkInfoEntry{ 2-bit BlkStatus, 14-bit P/E count }

`ifndef SIM_BRAM
// DRAM FFFF
// BRAM 0000
typedef enum { FREE_BLK, USED_BLK, BAD_BLK, DIRTY_BLK } BlkStatus deriving (Bits, Eq);
`else
// For testing. At BSIM, RAM is initialized to AAAAAAA
typedef enum { BAD_BLK, DIRTY_BLK, FREE_BLK, USED_BLK } BlkStatus deriving (Bits, Eq);
`endif

typedef struct {
	BlkStatus status; //2
	Bit#(TSub#(16, SizeOf#(BlkStatus))) erase; //14
} BlkInfoEntry deriving (Bits, Eq); // 16-bit (2-bytes) block info entry

typedef 8 BlkInfoEntriesPerWord;
typedef TLog#(BlkInfoEntriesPerWord) BlkInfoSelSz;
typedef Bit#(BlkInfoSelSz) BlkInfoSelT;
typedef Bit#(TSub#(TAdd#(SegmentTSz, VirtBlkTSz), BlkInfoSelSz)) BlkInfoTblAddr;
