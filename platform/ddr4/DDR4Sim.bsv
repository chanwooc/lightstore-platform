import Clocks::*;
import FIFO::*;
import Vector::*;
import RegFile::*;
import Connectable::*;
import GetPut::*;

import DDR4Controller::*;
import DDR4Common::*;

typedef Bit#(28) DDR4Address;
typedef Bit#(80) ByteEn;
typedef Bit#(640) DDR4Data;

Bool debug = False;

module mkDDR4Simulator(DDR4_User_VCU108);
	RegFile#(Bit#(25), DDR4Data) data <- mkRegFileFull();
	//Vector#(TExp#(26), Reg#(DDR4Data)) data <- replicateM(mkReg(0));
	FIFO#(DDR4Data) responses <- mkFIFO();
	
	Clock user_clock <- exposeCurrentClock;
	Reset user_reset_n <- exposeCurrentReset;
	
	// Rotate 512 bit word by offset 64 bit words.
	// function DDR4Data rotate(Bit#(3) offset, DDR4Data x);
	//		Vector#(8, Bit#(64)) words = unpack(x);
	//		Vector#(8, Bit#(64)) rotated = rotateBy(words, unpack((~offset) + 1));
	//		return pack(rotated);
	// endfunction
	
	//		 // Unrotate 512 bit word by offset 64 bit words.
	// function DDR4Data unrotate(Bit#(3) offset, DDR4Data x);
	//		Vector#(8, Bit#(64)) words = unpack(x);
	//		Vector#(8, Bit#(64)) unrotated = rotateBy(words, unpack(offset));
	//		return pack(unrotated);
	// endfunction
	
	// Vector#(32, FIFO#(DDR4Data)) delayQs <- replicateM(mkFIFO());
	
	// for (Integer i = 0; i < 31; i = i + 1) begin
	//		mkConnection(toGet(delayQs[i]), toPut(delayQs[i+1]));
	// end
	
	interface clock = user_clock;
	interface reset_n = user_reset_n;
	method Bool init_done() = True;
	
	method Action request(DDR4Address addr, ByteEn writeen, DDR4Data datain);
		if (debug) $display("%m, ddr req %h, %b, %h", addr, writeen, datain);
		Bit#(25) burstaddr = addr[27:3];
		Bit#(3) offset = addr[2:0];
		
		Bit#(640) mask = 0;
		for (Integer i = 0; i < 80; i = i+1) begin
			if (writeen[i] == 'b1) begin
				mask[(i*8+7):i*8] = 8'hFF;
			end
		end
		
		// Bit#(512) old_rotated = rotate(offset, data.sub(burstaddr));
		// //Bit#(512) old_rotated = rotate(offset, data[burstaddr]);
		// Bit#(512) new_masked = mask & datain;
		// Bit#(512) old_masked = (~mask) & old_rotated;
		// Bit#(512) new_rotated = new_masked | old_masked;
		// Bit#(512) new_unrotated = unrotate(offset, new_rotated);
		// data.upd(burstaddr, new_unrotated);
		//data[burstaddr] <=  new_unrotated;

	// leave for unrotated for now will figure out later
		let old_data = data.sub(burstaddr);
		let new_masked = mask & datain;
		let old_masked = (~mask) & old_data;
		let new_data = new_masked | old_masked;
		data.upd(burstaddr, new_data);
		
		if (writeen == 0) begin
			responses.enq(new_data);
			// delayQs[0].enq(new_rotated);
			// delayQs[0].enq(new_data);
		end
	endmethod
		
	method ActionValue#(DDR4Data) read_data;
		let v <- toGet(responses).get();
		// let v <- toGet(delayQs[31]).get();
		//$display("last, %d, %h", $time, v);
		if (debug) $display("%m, ddr resp %h", v);
		return v;
	endmethod
		
endmodule
