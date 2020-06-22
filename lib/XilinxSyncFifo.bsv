import Vector::*;

interface SyncFifoImport#(numeric type w);
	method Bool full;
	method Action enq(Bit#(w) x);
	method Bool empty;
	method Bit#(w) first;
	method Action deq;
endinterface
