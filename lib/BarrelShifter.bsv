import Vector::*;
import DefaultValue::*;
import ClientServer::*;
import SpecialFIFOs::*;
import Randomizable::*;

function Vector#(v, el) rotateRBy(Vector#(v, el) vect, UInt#(logv) n) provisos (Log#(v, logv));
	return reverse(rotateBy(reverse(vect), n));
endfunction

// Valid shiftBy value: 0~n-1
typedef struct {
	Bit#(n) data;
	Bit#(TLog#(n)) shiftBy;
	Bool isShiftLeft;
	Bool isRotate;
} BarrelBitReq#(numeric type n);

instance DefaultValue#(BarrelBitReq#(n));
	defaultValue = BarrelBitReq {
		data: 0,
		shiftBy: 0,
		isShiftLeft: False,
		isRotate: False
	};
endinstance

function Bit#(n) barrelBitShift (BarrelBitReq#(n) req) ;
	Integer numLevels = valueOf(TLog#(n));

	Vector#(TAdd#(TLog#(n),1), Bit#(n)) stageIn = newVector;
	stageIn[0] = req.data;

	for (Integer stage=0; stage < numLevels; stage = stage+1) begin
		Integer shiftBy = 2**stage;

		stageIn[stage+1] = stageIn[stage];
		Bit#(TAdd#(n, n)) rotate_replica = {stageIn[stage], stageIn[stage]};

		if (req.shiftBy[stage] == 1) begin // shift only if the stage bit is '1'
			if(req.isRotate) begin
				stageIn[stage+1] = (req.isShiftLeft)? truncateLSB( rotate_replica << fromInteger(shiftBy) )
													: truncate( rotate_replica >> fromInteger(shiftBy) );
			end
			else begin
				stageIn[stage+1] = (req.isShiftLeft)? stageIn[stage] << fromInteger(shiftBy)
													: stageIn[stage] >> fromInteger(shiftBy);
			end
		end
	end

	return stageIn[numLevels];
endfunction

typedef Server#(BarrelBitReq#(n), Bit#(n)) BarrelBitShift#(numeric type n);

// Valid shiftBy value: 0~n-1
typedef struct {
	Bit#(TMul#(numChunks, chunkSz)) data;
	Bit#(TLog#(numChunks)) shiftBy;
	Bool isShiftLeft;
	Bool isRotate;
} BarrelChunkReq#(numeric type numChunks, numeric type chunkSz);

instance DefaultValue#(BarrelChunkReq#(n, csz));
	defaultValue = BarrelChunkReq {
		data: 0,
		shiftBy: 0,
		isShiftLeft: True,
		isRotate: False
	};
endinstance

function Bit#(TMul#(n, csz)) barrelChunkShift (BarrelChunkReq#(n, csz) req) ;
	Integer numLevels = valueOf(TLog#(n));

	Vector#(TAdd#(TLog#(n),1), Bit#(TMul#(n, csz))) stageIn = newVector;
	stageIn[0] = req.data;

	for (Integer stage=0; stage < numLevels; stage = stage+1) begin
		Integer shiftBy = valueOf(csz) * (2**stage);

		stageIn[stage+1] = stageIn[stage];
		let rotate_replica = {stageIn[stage], stageIn[stage]};

		if (req.shiftBy[stage] == 1) begin // shift only if the stage bit is '1'
			if(req.isRotate) begin
				stageIn[stage+1] = (req.isShiftLeft)?  truncateLSB(rotate_replica << fromInteger(shiftBy))
													:  truncate(rotate_replica >> fromInteger(shiftBy));
			end
			else begin
				stageIn[stage+1] = (req.isShiftLeft)? stageIn[stage] << fromInteger(shiftBy)
													: stageIn[stage] >> fromInteger(shiftBy);
			end
		end
	end

	return stageIn[numLevels];
endfunction

// Valid shiftBy value: 0~wByte-1
typedef struct {
	Bit#(TMul#(8, wByte)) data;
	Bit#(TLog#(wByte)) shiftBy;
	Bool isShiftLeft;
	Bool isRotate;
} BarrelByteReq#(numeric type wByte);

instance DefaultValue#(BarrelByteReq#(wByte));
	defaultValue = BarrelByteReq {
		data: 0,
		shiftBy: 0,
		isShiftLeft: True,
		isRotate: False
	};
endinstance

function Bit#(TMul#(wByte, 8)) barrelByteShift (BarrelByteReq#(wByte) req) ;
	BarrelChunkReq#(wByte, 8) chunkReq =  BarrelChunkReq{ data: req.data, shiftBy: req.shiftBy, isShiftLeft: req.isShiftLeft, isRotate: req.isRotate };
	return barrelChunkShift(chunkReq);
endfunction

module mkTestBarrelBit (Empty);
	Randomize#(Bit#(32)) randomizer <- mkGenericRandomizer;
	Reg#(Bit#(32)) cycle <- mkReg(0);
	Reg#(Bool) started <- mkReg(False);

	rule initialize (!started);
		started <= True;
		randomizer.cntrl.init;
	endrule

	rule cycleCnt (started);
		cycle <= cycle+1;
	endrule

	rule job (started && cycle < 10);
		let randNum <- randomizer.next;
		let rotate_replica = {randNum, randNum};

		$display("cycle %d randNum %b", cycle, randNum);
		$display("test logical shift");
		for(Integer i=0; i<32; i=i+1) begin
			if (((randNum << fromInteger(i)) != barrelBitShift(BarrelBitReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: True, isRotate: False})) ||
				((randNum >> fromInteger(i)) != barrelBitShift(BarrelBitReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: False, isRotate: False}))) begin
				$display("mismatch shiftBy %d Result<< %b", i, barrelBitShift(BarrelBitReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: True, isRotate: False}));
				$display("mismatch shiftBy %d Result>> %b", i, barrelBitShift(BarrelBitReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: False, isRotate: False}));
			end
			else begin
				$display("pass logical shift! cycle:%d shiftBy:%d", cycle, i);
			end
		end

		$display("test rotational shift");
		for(Integer i=0; i<32; i=i+1) begin
			if( ((truncateLSB(rotate_replica<<fromInteger(i))) != barrelBitShift(BarrelBitReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: True, isRotate: True}))
				|| ((truncate(rotate_replica>>fromInteger(i))) != barrelBitShift(BarrelBitReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: False, isRotate: True})) ) begin
				$display("mismatch shiftBy %d Result<< %b", i, barrelBitShift(BarrelBitReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: True, isRotate: True}));
				$display("mismatch shiftBy %d Result>> %b", i, barrelBitShift(BarrelBitReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: False, isRotate: True}));
			end
			else begin
				$display("pass rotational shift! cycle:%d shiftBy:%d", cycle, i);
			end
		end
	endrule

	rule kill (cycle == 10);
		$finish;
	endrule
endmodule

module mkTestBarrelByte (Empty);

	Randomize#(Bit#(TMul#(32,8))) randomizer <- mkGenericRandomizer;
	Reg#(Bit#(32)) cycle <- mkReg(0);
	Reg#(Bool) started <- mkReg(False);

	rule initialize (!started);
		started <= True;
		randomizer.cntrl.init;
	endrule

	rule cycleCnt (started);
		cycle <= cycle+1;
	endrule

	rule job (started && cycle < 10);
		let randNum <- randomizer.next;
		let rotate_replica = {randNum, randNum};

		$display("cycle %d randNum %b", cycle, randNum);
		$display("test logical shift");
		for(Integer i=0; i<32; i=i+1) begin
			if (((randNum << fromInteger(8*i)) != barrelByteShift(BarrelByteReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: True, isRotate: False})) ||
				((randNum >> fromInteger(8*i)) != barrelByteShift(BarrelByteReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: False, isRotate: False}))) begin
				$display("mismatch shiftBy %dB Result<< %b", i, barrelByteShift(BarrelByteReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: True, isRotate: False}));
				$display("mismatch shiftBy %dB Result>> %b", i, barrelByteShift(BarrelByteReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: False, isRotate: False}));
			end
			else begin
				$display("pass logical shift! cycle:%d shiftBy:%d", cycle, i);
			end
		end

		$display("test rotational shift");
		for(Integer i=0; i<32; i=i+1) begin
			if( ((truncateLSB(rotate_replica<<fromInteger(8*i))) != barrelByteShift(BarrelByteReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: True, isRotate: True}))
				|| ((truncate(rotate_replica>>fromInteger(8*i))) != barrelByteShift(BarrelByteReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: False, isRotate: True})) ) begin
				$display("mismatch shiftBy %dB Result<< %b", 8*i, barrelByteShift(BarrelByteReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: True, isRotate: True}));
				$display("mismatch shiftBy %dB Result>> %b", 8*i, barrelByteShift(BarrelByteReq{data: randNum, shiftBy: fromInteger(i), isShiftLeft: False, isRotate: True}));
			end
			else begin
				$display("pass rotational shift! cycle:%d shiftBy:%d", cycle, i);
			end
		end
	endrule

	rule kill (cycle == 10);
		$finish;
	endrule
endmodule
