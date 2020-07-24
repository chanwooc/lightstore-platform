import FIFOF::*;
import FIFO::*;
import BarrelShifter::*;

interface StreamingDeserializerIfc#(type tFrom, type tTo);
	method ActionValue#(tTo) deq;
	method Action enq(tFrom in, Bool cont);
endinterface

module mkStreamingDeserializer (StreamingDeserializerIfc#(tFrom, tTo))
	provisos(
		Bits#(tFrom, tFromSz)
		, Bits#(tTo, tToSz)
		, Add#(tFromSz, __a, tToSz)
		//, Log#(tFromSz, tFromSzLog)
	);
	Integer fromSz = valueOf(tFromSz);
	Integer toSz = valueOf(tToSz);

	Reg#(Bit#(TAdd#(TLog#(tToSz),1))) outCounter <- mkReg(0);
	Reg#(Bit#(tToSz)) outBuffer <- mkReg(0);

	FIFO#(tTo) outQ <- mkFIFO;

	// inQ added for pipelining to meet timing constraints
	FIFO#(Tuple2#(tFrom, Bool)) inQ <- mkFIFO;

	rule deserialize;
		match{.in, .cont} = inQ.first;
		inQ.deq;

		let inData = pack(in);

		// Orig
		// Bit#(tToSz) nextBuffer = outBuffer | (zeroExtend(inData)<<outCounter);

		// Barrel - alternative (two barrel shifters for deserializer)
		let req1 = BarrelBitReq{ data: zeroExtend(inData), shiftBy: truncate(outCounter), isShiftLeft: True, isRotate: False };
		Bit#(tToSz) nextBuffer = outBuffer | barrelBitShift( req1 );

		// Barrel - (share one barrel shifter for deserializer) - Worse Timing
		// let req1 = BarrelBitReq{ data: zeroExtend(inData), shiftBy: truncate(outCounter), isShiftLeft: True, isRotate: True };
		// Bit#(tToSz) rotated = barrelBitShift(req1);
		// Bit#(tToSz) nextBuffer = outBuffer | ( rotated & ~((1<<outCounter)-1)  );

		if ( outCounter + fromInteger(fromSz) > fromInteger(toSz) ) begin
			let over = outCounter + fromInteger(fromSz) - fromInteger(toSz);
			outQ.enq(unpack(nextBuffer));
			if ( cont ) begin
				outCounter <= over;
				let minus = fromInteger(toSz) - outCounter;
				// Orig
				// outBuffer <= (zeroExtend(inData) >> minus);

				// Barrel - alternative (separate shifter)
				let req2 = BarrelBitReq{ data: zeroExtend(inData), shiftBy: truncate(minus), isShiftLeft: False, isRotate: False };
				outBuffer <= barrelBitShift( req2 );

				// Barrel - (sharing the one above)
				// outBuffer <= rotated & ((1<<outCounter)-1);

				//$display( "%x >%d %d %x", inData, over,outCounter, inData >> minus );
			end else begin
				outCounter <= 0;
				outBuffer <= 0;
			end
		end
		else if ( outCounter + fromInteger(fromSz) == fromInteger(toSz) ) begin
			outBuffer <= 0;
			outCounter <= 0;
			outQ.enq(unpack(nextBuffer));
		end else if ( cont ) begin
			outBuffer <= nextBuffer;
			outCounter <= outCounter + fromInteger(fromSz);
			//$display( "outcounter -> %d", outCounter + fromInteger(fromSz) );
		end else begin
			outBuffer <= 0;
			outCounter <= 0;
		end
	endrule

	method ActionValue#(tTo) deq;
		outQ.deq;
		return outQ.first;
	endmethod

	method Action enq(tFrom in, Bool cont);
		inQ.enq(tuple2(in,cont));
	endmethod
endmodule

interface StreamingSerializerIfc#(type tFrom, type tTo);
	method ActionValue#(Tuple2#(tTo,Bool)) deq;
	method Action enq(tFrom in);
endinterface

module mkStreamingSerializer (StreamingSerializerIfc#(tFrom, tTo))
	provisos(
		Bits#(tFrom, tFromSz)
		, Bits#(tTo, tToSz)
		, Add#(tToSz, __a, tFromSz)
		//, Log#(tFromSz, tFromSzLog)
	);

	Integer fromSz = valueOf(tFromSz);
	Integer toSz = valueOf(tToSz);

	FIFOF#(Bit#(tFromSz)) inQ <- mkFIFOF;
	Reg#(Bit#(TAdd#(TLog#(tFromSz),1))) inCounter <- mkReg(0);
	Reg#(Maybe#(Bit#(tFromSz))) inBuffer <- mkReg(tagged Invalid);

	FIFO#(Tuple2#(tTo, Bool)) outQ <- mkFIFO;

	rule serialize;
		Bit#(tFromSz) inBufferData = fromMaybe(?, inBuffer);

		// Orig
		// Bit#(tToSz) outData = truncate(inBufferData>>inCounter);

		// Barrel
		BarrelBitReq#(tFromSz)
		  req1 = BarrelBitReq{ data: inBufferData, shiftBy: truncate(inCounter), isShiftLeft: False, isRotate: False };
		Bit#(tToSz) outData = truncate(barrelBitShift( req1 ));

		if ( !isValid(inBuffer) ) begin
			inQ.deq;
			inBuffer <= tagged Valid inQ.first;
			inCounter <= 0;
		end else if ( inCounter + fromInteger(toSz) == fromInteger(fromSz) ) begin
			outQ.enq(tuple2(unpack(outData), True));
			inCounter <= 0;
			if ( inQ.notEmpty ) begin
				Bit#(tFromSz) fromData = inQ.first;
				inQ.deq;
				inBuffer <= tagged Valid fromData;
			end else begin
				inBuffer <= tagged Invalid;
			end
		end else if ( inCounter + fromInteger(toSz) > fromInteger(fromSz) ) begin
			if ( inQ.notEmpty ) begin
				Bit#(tFromSz) fromData = inQ.first;
				inQ.deq;
				inBuffer <= tagged Valid fromData;

				let over = inCounter + fromInteger(toSz) - fromInteger(fromSz);

				// Orig
				// Bit#(tToSz) combData = truncate( fromData << (fromInteger(toSz) -over)) | outData;
				
				// Barrel - (cannot share the one above)
				BarrelBitReq#(tFromSz)
				  req2 = BarrelBitReq{ data: fromData, shiftBy: truncate(fromInteger(toSz)-over), isShiftLeft: True, isRotate: False };
				Bit#(tToSz) combData = truncate(barrelBitShift( req2 )) | outData;
				
				outQ.enq(tuple2(unpack(combData), True));
				inCounter <= over;
			end else begin
				outQ.enq(tuple2(unpack(outData), False));
				inCounter <= 0;
				inBuffer <= tagged Invalid;
			end
		end else begin
			outQ.enq(tuple2(unpack(outData), True));
			inCounter <= inCounter + fromInteger(toSz);
		end
	endrule


	method ActionValue#(Tuple2#(tTo,Bool)) deq; // value, continue?
		outQ.deq;
		let d = outQ.first;
		let data = tpl_1(d);
		let cont = tpl_2(d);
		return tuple2(data,cont);
	endmethod
	method Action enq(tFrom in);
		inQ.enq(pack(in));
	endmethod
endmodule
