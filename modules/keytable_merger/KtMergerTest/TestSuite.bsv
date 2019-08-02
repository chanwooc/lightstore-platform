import BRAM::*;
import KeytableMerger::*;

Integer highLvlKT = 41; //52
Integer lowLvlKT = 88; //52

module mkTest(Empty);
	BRAM_Configure lowLvlBufCfg = defaultValue;
	lowLvlBufCfg.memorySize = lowLvlKT*512; // 1 page = 8192 KB = 512 * 16B
	lowLvlBufCfg.loadFormat = tagged Hex "bram/addr/l_level.bram";

	BRAM1Port#(Bit#(32), Bit#(128)) lowLvlBram <- mkBRAM1Server(lowLvlBufCfg);

	BRAM_Configure highLvlBufCfg = defaultValue;
	highLvlBufCfg.memorySize = highLvlKT*512; // 1 page = 8192 KB = 512 * 16B
	highLvlBufCfg.loadFormat = tagged Hex "bram/addr/h_level.bram";

	BRAM1Port#(Bit#(32), Bit#(128)) highLvlBram <- mkBRAM1Server(highLvlBufCfg);

	KeytableMerger merger <- mkKeytableMerger;

	Reg#(Bit#(32)) cnt <- mkReg(0);

	Reg#(Bit#(32)) lowGenAddrReg <- mkReg(0);

	Reg#(Bool) cmdSent <- mkReg(False);

	rule doCnt;
		if (cnt == 0) begin
			merger.runMerge(fromInteger(highLvlKT), fromInteger(lowLvlKT));
		end
		cnt <= cnt + 1;
	endrule

	rule l_generateReq (lowGenAddrReg < fromInteger(512*lowLvlKT));
		lowGenAddrReg <= lowGenAddrReg + 1;
		lowLvlBram.portA.request.put( BRAMRequest{ write: False, responseOnWrite: False, address: (lowGenAddrReg), datain: ?} );

		//if (lowGenAddrReg[8:0]==511)
		//	$display("Low page %d", lowGenAddrReg>>9);
	endrule

	Reg#(Bit#(32)) highGenAddrReg <- mkReg(0);

	rule h_generateReq (highGenAddrReg < fromInteger(512*highLvlKT));
		highGenAddrReg <= highGenAddrReg + 1;
		highLvlBram.portA.request.put( BRAMRequest{ write: False, responseOnWrite: False, address: (highGenAddrReg), datain: ?} );

		//if (highGenAddrReg[8:0]==511)
		//	$display("High page %d", highGenAddrReg>>9);
	endrule

	rule h_push;
		let d <- highLvlBram.portA.response.get();
		merger.enqHighLevelKt(d);
	endrule

	rule l_push;
		let d <- lowLvlBram.portA.response.get();
		merger.enqLowLevelKt(d);
	endrule

	Reg#(Bit#(32)) mergerOutputCnt <- mkReg(0);
	rule printOutput;
		mergerOutputCnt <= mergerOutputCnt+1;
		let data <- merger.getMergedKt();

		let d = tpl_2(data);
		Bit#(1) f = pack(tpl_1(data));

		$display("%x%x%x%x%x%x%x%x",d[127:112], d[111:96], d[95:80], d[79:64], d[63:48], d[47:32], d[31:16], d[15:0]);

		Bit#(9) beatTruncate = truncate(mergerOutputCnt);
		if (f==1 && beatTruncate == 511 )
			$finish;
	endrule

	rule printCollectedAddr;
		let addr <- merger.getCollectedAddr();
		//$display("%x", addr);
	endrule
endmodule
