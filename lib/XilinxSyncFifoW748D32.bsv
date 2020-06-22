import FIFOF::*;
import XilinxSyncFifo::*;
import Clocks::*;

import "BVI" sync_fifo_w748_d32 =
module mkSyncFifoImport_w748_d32#(Clock srcClk, Clock dstClk)(SyncFifoImport#(748));
	default_clock no_clock;
	default_reset no_reset;
	input_clock (wr_clk) = srcClk;
	input_clock (rd_clk) = dstClk;

	method full full() clocked_by(srcClk) reset_by(no_reset);
	method enq(din) enable(wr_en) clocked_by(srcClk) reset_by(no_reset);
	method empty empty() clocked_by(dstClk) reset_by(no_reset);
	method dout first() clocked_by(dstClk) reset_by(no_reset);
	method deq() enable(rd_en) clocked_by(dstClk) reset_by(no_reset);

	schedule (full, enq) CF (empty, first, deq);
	schedule (full) CF (full, enq);
	schedule (enq) C (enq);
	schedule (empty, first) CF (empty, first, deq);
	schedule (deq) C (deq);
endmodule

import "BVI" sync_bram_fifo_w748_d32 =
module mkSyncBramFifoImport_w748_d32#(Clock srcClk, Clock dstClk)(SyncFifoImport#(748));
	default_clock no_clock;
	default_reset no_reset;
	input_clock (wr_clk) = srcClk;
	input_clock (rd_clk) = dstClk;

	method full full() clocked_by(srcClk) reset_by(no_reset);
	method enq(din) enable(wr_en) clocked_by(srcClk) reset_by(no_reset);
	method empty empty() clocked_by(dstClk) reset_by(no_reset);
	method dout first() clocked_by(dstClk) reset_by(no_reset);
	method deq() enable(rd_en) clocked_by(dstClk) reset_by(no_reset);

	schedule (full, enq) CF (empty, first, deq);
	schedule (full) CF (full, enq);
	schedule (enq) C (enq);
	schedule (empty, first) CF (empty, first, deq);
	schedule (deq) C (deq);
endmodule

// wrap up imported BSV or simulation module
(* no_default_clock, no_default_reset *)
module mkSyncFifo_w748_d32#(Clock srcClk, Reset srcRst, Clock dstClk)(SyncFIFOIfc#(t)) provisos (Bits#(t, 748));
if ( !genVerilog() ) begin
	SyncFIFOIfc#(t) q <- mkSyncFIFO(32, srcClk, srcRst, dstClk);
	return q;
end
else begin
	SyncFifoImport#(748) q <- mkSyncFifoImport_w748_d32(srcClk, dstClk);

	method notFull = !q.full;
	method Action enq(t x) if(!q.full);
		q.enq(pack(x));
	endmethod
	method notEmpty = !q.empty;
	method t first if(!q.empty);
		return unpack(q.first);
	endmethod
	method Action deq if(!q.empty);
		q.deq;
	endmethod
end
endmodule

(* no_default_clock, no_default_reset *)
module mkSyncBramFifo_w748_d32#(Clock srcClk, Reset srcRst, Clock dstClk)(SyncFIFOIfc#(t)) provisos (Bits#(t, 748));
if ( !genVerilog() ) begin
	SyncFIFOIfc#(t) q <- mkSyncFIFO(32, srcClk, srcRst, dstClk);
	return q;
end
else begin
	SyncFifoImport#(748) q <- mkSyncBramFifoImport_w748_d32(srcClk, dstClk);

	method notFull = !q.full;
	method Action enq(t x) if(!q.full);
		q.enq(pack(x));
	endmethod
	method notEmpty = !q.empty;
	method t first if(!q.empty);
		return unpack(q.first);
	endmethod
	method Action deq if(!q.empty);
		q.deq;
	endmethod
end
endmodule
