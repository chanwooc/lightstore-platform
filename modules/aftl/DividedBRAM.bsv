import BRAM::*;
import BRAMFIFO::*;
import FIFO::*;
import SpecialFIFOs::*;

import Vector::*;

typedef BRAM2Port#(addr, data) DividedBRAM2Port#(type addr, type data, numeric type logNumBram);

module mkDividedBRAM #( BRAM_Configure cfg ) ( DividedBRAM2Port #(addr, data, logNumBram) )
	provisos( Bits#(addr, addr_sz), Bits#(data, data_sz), Add#(logNumBram, subbram_addr_sz, addr_sz) );

	if (cfg.allowWriteResponseBypass == True) error("[DividedBRAM] allowWriteResponseBypass should be False");

	Vector#(TExp#(logNumBram), BRAM2Port#(Bit#(subbram_addr_sz), data)) vec_bram <- replicateM(mkBRAM2Server(cfg));

	FIFO#(BRAMRequest#(addr, data)) reqQ_A <- mkPipelineFIFO;
	FIFO#(BRAMRequest#(addr, data)) reqQ_B <- mkPipelineFIFO;

	FIFO#(data) respQ_A <- mkPipelineFIFO;
	FIFO#(data) respQ_B <- mkPipelineFIFO;

	FIFO#(Bit#(logNumBram)) pendingReq_A <- mkSizedFIFO(cfg.outFIFODepth * valueOf(TExp#(logNumBram)));
	FIFO#(Bit#(logNumBram)) pendingReq_B <- mkSizedFIFO(cfg.outFIFODepth * valueOf(TExp#(logNumBram)));

	rule reqA;
		let req <- toGet(reqQ_A).get;
		Bit#(logNumBram) bramSel = truncate(pack(req.address));

		vec_bram[bramSel].portA.request.put( 
			BRAMRequest{
				write: req.write, responseOnWrite: req.responseOnWrite,
				address: truncate(pack(req.address) >> valueOf(logNumBram)), datain: req.datain
			}
		);

		if ( !req.write || req.responseOnWrite ) pendingReq_A.enq( bramSel );
	endrule

	rule reqB;
		let req <- toGet(reqQ_B).get;
		Bit#(logNumBram) bramSel = truncate(pack(req.address));

		vec_bram[bramSel].portB.request.put( 
			BRAMRequest{
				write: req.write, responseOnWrite: req.responseOnWrite,
				address: truncate(pack(req.address) >> valueOf(logNumBram)), datain: req.datain
			}
		);
		if ( !req.write || req.responseOnWrite ) pendingReq_B.enq( bramSel );
	endrule

	rule respA;
		let bramSel <- toGet(pendingReq_A).get;
		let ret <- vec_bram[bramSel].portA.response.get;
		respQ_A.enq(ret);

	endrule

	rule respB;
		let bramSel <- toGet(pendingReq_B).get;
		let ret <- vec_bram[bramSel].portB.response.get;
		respQ_B.enq(ret);
	endrule


	interface BRAMServer portA;
		interface Put request = toPut(reqQ_A);
		interface Get response = toGet(respQ_A);
	endinterface

	interface BRAMServer portB;
		interface Put request = toPut(reqQ_B);
		interface Get response = toGet(respQ_B);
	endinterface


	method Action portAClear;
		function Action _clearA (BRAM2Port#(Bit#(x), data) svr) = svr.portAClear;
		mapM_(_clearA, vec_bram);
		reqQ_A.clear;
		respQ_A.clear;
		pendingReq_A.clear;
	endmethod

	method Action portBClear;
		function Action _clearB (BRAM2Port#(Bit#(x), data) svr) = svr.portBClear;
		mapM_(_clearB, vec_bram);
		reqQ_B.clear;
		respQ_B.clear;
		pendingReq_B.clear;
	endmethod
endmodule
