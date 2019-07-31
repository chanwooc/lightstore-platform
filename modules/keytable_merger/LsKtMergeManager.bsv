import DefaultValue::*;
import FIFOF::*;
import FIFO::*;
import FIFOLevel::*;
import BRAMFIFO::*;
import BRAM::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

import Vector::*;
import BuildVector::*;
import List::*;

import ConnectalMemory::*;
import ConnectalConfig::*;
import ConnectalMemTypes::*;
import MemReadEngine::*;
import MemWriteEngine::*;
import Pipe::*;
import Leds::*;

import Clocks :: *;
import Xilinx       :: *;
`ifndef BSIM
import XilinxCells ::*;
`endif

import ControllerTypes::*;
import KeytableMerger::*;
import KtAddrManager::*;


// LightStore Keytable Merge Manager
interface LsKtMergeManager;
	method Action startGetPPA(Bit#(32) numKtHigh, Bit#(32) numKtLow);
	method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
//	method Action setDmaMergedKtRef(Bit#(32) sgId);
//	method Action setDmaInvalPPARef(Bit#(32) sgId);

//	method ActionValue#(FlashCmd) getFlashReq();
//	method Action enqFlashWordRead(Tuple2#(Bit#(WordSz), TagT) taggedRdata);
//	method ActionValue#(Tuple2#(Bit#(WordSz), TagT)) getFlashWordWrite();
//	method Action flashWriteReq(TagT tag);

// TODO: below are methods for testing
	method ActionValue#(Bit#(32)) getPPAHigh();
	method ActionValue#(Bit#(32)) getPPALow();
endinterface

// Supposed to use tags: 64~127 (tag[7]=1)
//  For read PPAs (High, Low), we split tags 32 / 32 (tag[6]=High?)
module mkLsKtMergeManager #(
	Vector#(4, MemReadEngineServer#(DataBusWidth)) rs,
	Vector#(2, MemWriteEngineServer#(DataBusWidth)) ws
) (LsKtMergeManager);

	KtAddrManager addrManager <- mkKtAddrManager(rs);
	KeytableMerger ktMerger <- mkKeytableMerger;

	// Reorder Flash reads

	// 1. Init tag
	FIFOF#(TagT) readKtHighTagQ <- mkFIFOF;
	FIFOF#(TagT) readKtLowTagQ <- mkFIFOF;
	

	method Action startGetPPA(Bit#(32) numKtHigh, Bit#(32) numKtLow);
		addrManager.startGetPPA(numKtHigh, numKtLow);
	endmethod
	method Action setDmaKtPPARef(Bit#(32) sgIdHigh, Bit#(32) sgIdLow, Bit#(32) sgIdRes);
		addrManager.setDmaKtPPARef(sgIdHigh, sgIdLow, sgIdRes);
	endmethod

//	method ActionValue#(Bit#(32)) getPPAHigh();
//		let d <- addrManager.getPPAHigh;
//		return d;
//	endmethod
//	method ActionValue#(Bit#(32)) getPPALow();
//		let d <- addrManager.getPPALow;
//		return d;
//	endmethod
endmodule
