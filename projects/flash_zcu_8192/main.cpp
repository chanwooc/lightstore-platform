#include <stdio.h>
#include <sys/mman.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <monkit.h>
#include <semaphore.h>

//#include <list>
#include <time.h>

//#include "StdDmaIndication.h"
//#include "MemServerRequest.h"
//#include "MMURequest.h"
#include "dmaManager.h"

#include "FlashIndication.h"
#include "FlashRequest.h"

#define BLOCKS_PER_CHIP 4096 // 4096
#define CHIPS_PER_BUS 8 // 8
#define NUM_BUSES 8 // 8

//#define FPAGE_SIZE (8192*2)
//#define FPAGE_SIZE_VALID (8224)
#define FPAGE_SIZE (8192)
#define FPAGE_SIZE_VALID (8192)
#define NUM_TAGS 128

typedef enum {
	UNINIT,
	ERASED,
	WRITTEN
} FlashStatusT;

typedef struct {
	bool busy;
	int bus;
	int chip;
	int block;
	int page;
} TagTableEntry;

FlashRequestProxy *device;

pthread_mutex_t flashReqMutex;
pthread_cond_t flashFreeTagCond;

//8k * 128
size_t dstAlloc_sz = FPAGE_SIZE * NUM_TAGS * sizeof(unsigned char);
size_t srcAlloc_sz = FPAGE_SIZE * NUM_TAGS * sizeof(unsigned char);
int dstAlloc;
int srcAlloc;
unsigned int ref_dstAlloc;
unsigned int ref_srcAlloc;
unsigned int* dstBuffer;
unsigned int* srcBuffer;
unsigned int* readBuffers[NUM_TAGS];
unsigned int* writeBuffers[NUM_TAGS];
TagTableEntry readTagTable[NUM_TAGS];
TagTableEntry writeTagTable[NUM_TAGS];
TagTableEntry eraseTagTable[NUM_TAGS];
FlashStatusT flashStatus[NUM_BUSES][CHIPS_PER_BUS][BLOCKS_PER_CHIP];

int MYPAGE = 256; // Max 256 Valid only if writing to page 0->1->2 ...

bool testPassed = false;
bool verbose = false;
int curReadsInFlight = 0;
int curWritesInFlight = 0;
int curErasesInFlight = 0;

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}


unsigned int hashAddrToData(int bus, int chip, int blk, int word) {
	return ((bus<<24) + (chip<<20) + (blk<<16) + word);
}


bool checkReadData(int tag) {
	TagTableEntry e = readTagTable[tag];
    bool pass = true;

	unsigned int goldenData;
	if (flashStatus[e.bus][e.chip][e.block]==WRITTEN) {
		int numErrors = 0;
		for (unsigned int word=0; word<FPAGE_SIZE_VALID/sizeof(unsigned int); word++) {
			goldenData = hashAddrToData(e.bus, e.chip, e.block, word);
			if (goldenData != readBuffers[tag][word]) {
				fprintf(stderr, "LOG: **ERROR: read data mismatch! tag=%d, %d %d %d %d, word=%d, Expected: %x, read: %x\n", tag, e.bus, e.chip, e.block, e.page, word, goldenData, readBuffers[tag][word]);
				numErrors++;
				pass = false;
				break;
			}
		}

		if (numErrors==0) {
			fprintf(stderr, "LOG: Read data check passed on tag=%d!\n", tag);
		}
	}
	else if (flashStatus[e.bus][e.chip][e.block]==ERASED) {
		if (readBuffers[tag][0]==(unsigned int)-1) {
			fprintf(stderr, "LOG: Read check pass on erased block!\n");
		}
		else if (readBuffers[tag][0]==0) {
			fprintf(stderr, "LOG: Warning: potential bad block, read erased data 0\n");
			pass = false;
		}
		else {
			fprintf(stderr, "LOG: **ERROR: read data mismatch! Expected: ERASED, read: %x\n", readBuffers[tag][0]);
			pass = false;
		}
	}
	else {
		fprintf(stderr, "LOG: **ERROR: flash block state unknown. Did you erase before write?\n");
		pass = false;
	}
    return pass;
}

class FlashIndication: public FlashIndicationWrapper {
	public:
		FlashIndication(unsigned int id) : FlashIndicationWrapper(id){}

		virtual void readDone(unsigned int tag) {
//			bool tempPassed = true;

			if ( verbose ) {
				printf( "LOG: pagedone: tag=%d; inflight=%d\n", tag, curReadsInFlight );
				fflush(stdout);
			}

			//check 
//			tempPassed = checkReadData(tag);

			pthread_mutex_lock(&flashReqMutex);
//			if ( tempPassed == false ) {
//				testPassed = false;
//				printf("LOG: **ERROR: check read data failed @ tag=%d\n",tag);
//			}
			if ( curReadsInFlight < 0 ) {
				fprintf(stderr, "LOG: **ERROR: Read requests in flight cannot be negative %d\n", curReadsInFlight );
			}
			if ( readTagTable[tag].busy == false ) {
				fprintf(stderr, "LOG: **ERROR: received unused buffer read done (duplicate) tag=%d\n", tag);
				fflush(stderr);
				testPassed = false;
			} else {
				curReadsInFlight --;
			}

			readTagTable[tag].busy = false;

			pthread_mutex_unlock(&flashReqMutex);
		}

		virtual void writeDone(unsigned int tag) {
			if (verbose) {
				printf("LOG: writedone, tag=%d\n", tag); fflush(stdout);
			}

			pthread_mutex_lock(&flashReqMutex);
			if ( curWritesInFlight < 0 ) {
				fprintf(stderr, "LOG: **ERROR: Write requests in flight cannot be negative %d\n", curWritesInFlight );
			}
			if ( writeTagTable[tag].busy == false) {
				fprintf(stderr, "LOG: **ERROR: received unknown write done (duplicate) tag=%d\n", tag);
				fflush(stderr);
				testPassed = false;
			} else {
				curWritesInFlight --;
			}
			writeTagTable[tag].busy = false;
			pthread_mutex_unlock(&flashReqMutex);
		}

		virtual void eraseDone(unsigned int tag, unsigned int status) {
			printf("LOG: eraseDone, tag=%d, status=%d\n", tag, status); fflush(stdout);
			if (status != 0) {
				printf("LOG: detected bad block with tag = %d\n", tag);
			}
			pthread_mutex_lock(&flashReqMutex);
			curErasesInFlight--;
			if ( curErasesInFlight < 0 ) {
				fprintf(stderr, "LOG: **ERROR: erase requests in flight cannot be negative %d\n", curErasesInFlight );
				curErasesInFlight = 0;
			}
			if ( eraseTagTable[tag].busy == false ) {
				fprintf(stderr, "LOG: **ERROR: received unused tag erase done %d\n", tag);
				testPassed = false;
			}
			eraseTagTable[tag].busy = false;
			pthread_mutex_unlock(&flashReqMutex);
		}

		virtual void debugDumpResp (unsigned int debug0, unsigned int debug1,  unsigned int debug2, unsigned int debug3, unsigned int debug4, unsigned int debug5) {
			//uint64_t cntHi = debugRdCntHi;
			//uint64_t rdCnt = (cntHi<<32) + debugRdCntLo;
			fprintf(stderr, "LOG: DEBUG DUMP: gearSend = %d, gearRec = %d, aurSend = %d, aurRec = %d, readSend=%d, writeSend=%d\n", debug0, debug1, debug2, debug3, debug4, debug5);
		}


};




int getNumReadsInFlight() { return curReadsInFlight; }
int getNumWritesInFlight() { return curWritesInFlight; }
int getNumErasesInFlight() { return curErasesInFlight; }

//TODO: more efficient locking
int waitIdleEraseTag() {
	int tag = -1;
	while ( tag < 0 ) {
	pthread_mutex_lock(&flashReqMutex);

		for ( int t = 0; t < NUM_TAGS; t++ ) {
			if ( !eraseTagTable[t].busy ) {
				eraseTagTable[t].busy = true;
				tag = t;
				break;
			}
		}
	pthread_mutex_unlock(&flashReqMutex);
		/*
		if (tag < 0) {
			pthread_cond_wait(&flashFreeTagCond, &flashReqMutex);
		}
		else {
			pthread_mutex_unlock(&flashReqMutex);
			return tag;
		}
		*/
	}
	return tag;
}


//TODO: more efficient locking
int waitIdleWriteBuffer() {
	int tag = -1;
	while ( tag < 0 ) {
	pthread_mutex_lock(&flashReqMutex);

		for ( int t = 0; t < NUM_TAGS; t++ ) {
			if ( !writeTagTable[t].busy) {
				writeTagTable[t].busy = true;
				tag = t;
				break;
			}
		}
	pthread_mutex_unlock(&flashReqMutex);
		/*
		if (tag < 0) {
			pthread_cond_wait(&flashFreeTagCond, &flashReqMutex);
		}
		else {
			pthread_mutex_unlock(&flashReqMutex);
			return tag;
		}
		*/
	}
	return tag;
}



//TODO: more efficient locking
int waitIdleReadBuffer() {
	int tag = -1;
	while ( tag < 0 ) {
	pthread_mutex_lock(&flashReqMutex);

		for ( int t = 0; t < NUM_TAGS; t++ ) {
			if ( !readTagTable[t].busy ) {
				readTagTable[t].busy = true;
				tag = t;
				break;
			}
		}
	pthread_mutex_unlock(&flashReqMutex);
		/*
		if (tag < 0) {
			pthread_cond_wait(&flashFreeTagCond, &flashReqMutex);
		}
		else {
			pthread_mutex_unlock(&flashReqMutex);
			return tag;
		}
		*/
	}
	return tag;
}

void eraseBlock(uint32_t bus, uint32_t chip, uint32_t block, uint32_t tag) {
	pthread_mutex_lock(&flashReqMutex);
	curErasesInFlight ++;
	flashStatus[bus][chip][block] = ERASED;
	pthread_mutex_unlock(&flashReqMutex);

	if ( verbose ) fprintf(stderr, "LOG: sending erase block request with tag=%d @%d %d %d 0\n", tag, bus, chip, block );
	device->eraseBlock(bus,chip,block,tag);
}



void writePage(uint32_t bus, uint32_t chip, uint32_t block, uint32_t page, uint32_t tag) {
	pthread_mutex_lock(&flashReqMutex);
	curWritesInFlight ++;
	flashStatus[bus][chip][block] = WRITTEN;
	pthread_mutex_unlock(&flashReqMutex);

	if ( verbose ) fprintf(stderr, "LOG: sending write page request with tag=%d @%d %d %d %d\n", tag, bus, chip, block, page );
	device->writePage(bus,chip,block,page,tag,tag*FPAGE_SIZE);
}

void readPage(uint32_t bus, uint32_t chip, uint32_t block, uint32_t page, uint32_t tag) {
	pthread_mutex_lock(&flashReqMutex);
	curReadsInFlight ++;
	readTagTable[tag].bus = bus;
	readTagTable[tag].chip = chip;
	readTagTable[tag].block = block;
	readTagTable[tag].page = page;
	pthread_mutex_unlock(&flashReqMutex);

	if ( verbose ) fprintf(stderr, "LOG: sending read page request with tag=%d @%d %d %d %d\n", tag, bus, chip, block, page );
	device->readPage(bus,chip,block,page,tag,tag*FPAGE_SIZE);
}


int main(int argc, const char **argv)
{
	testPassed=true;

	fprintf(stderr, "Initializing Connectal & DMA...\n");

	device = new FlashRequestProxy(IfcNames_FlashRequestS2H);
	FlashIndication deviceIndication(IfcNames_FlashIndicationH2S);
    DmaManager *dma = platformInit();

	fprintf(stderr, "Main::allocating memory...\n");
	
	// Memory for DMA
	srcAlloc = portalAlloc(srcAlloc_sz, 0);
	dstAlloc = portalAlloc(dstAlloc_sz, 0);
	srcBuffer = (unsigned int *)portalMmap(srcAlloc, srcAlloc_sz);
	dstBuffer = (unsigned int *)portalMmap(dstAlloc, dstAlloc_sz);

	fprintf(stderr, "dstAlloc = %x\n", dstAlloc); 
	fprintf(stderr, "srcAlloc = %x\n", srcAlloc); 
	
	pthread_mutex_init(&flashReqMutex, NULL);
	pthread_cond_init(&flashFreeTagCond, NULL);

	printf( "Done initializing hw interfaces\n" ); fflush(stdout);

	portalCacheFlush(dstAlloc, dstBuffer, dstAlloc_sz, 1);
	portalCacheFlush(srcAlloc, srcBuffer, srcAlloc_sz, 1);
	ref_dstAlloc = dma->reference(dstAlloc);
	ref_srcAlloc = dma->reference(srcAlloc);

	device->setDmaWriteRef(ref_dstAlloc);
	device->setDmaReadRef(ref_srcAlloc);
	for (int t = 0; t < NUM_TAGS; t++) {
		readTagTable[t].busy = false;
		writeTagTable[t].busy = false;

		int byteOffset = t * FPAGE_SIZE;
		readBuffers[t] = dstBuffer + byteOffset/sizeof(unsigned int);
		writeBuffers[t] = srcBuffer + byteOffset/sizeof(unsigned int);
	}
	
	for (int blk=0; blk < BLOCKS_PER_CHIP; blk++) {
		for (int c=0; c < CHIPS_PER_BUS; c++) {
			for (int bus=0; bus< NUM_BUSES; bus++) {
				flashStatus[bus][c][blk] = UNINIT;
			}
		}
	}


	for (int t = 0; t < NUM_TAGS; t++) {
		for ( unsigned int i = 0; i < FPAGE_SIZE/sizeof(unsigned int); i++ ) {
			readBuffers[t][i] = 0xDEADBEEF;
			writeBuffers[t][i] = 0xBEEFDEAD;
		}
	}

	long actualFrequency=0;
	long requestedFrequency=1e9/MainClockPeriod;
	int status = setClockFrequency(0, requestedFrequency, &actualFrequency);
	fprintf(stderr, "Requested Freq: %5.2f, Actual Freq: %5.2f, status=%d\n"
			,(double)requestedFrequency*1.0e-6
			,(double)actualFrequency*1.0e-6,status);

	printf( "Start!\n" ); fflush(stdout);
	device->start(0);
	device->setDebugVals(0,0); //flag, delay

	device->debugDumpReq(0);
	sleep(1);

	int elapsed = 10000;

	printf( "TEST ERASE STARTED!\n" ); fflush(stdout);
	//test erases
	for (int blk = 0; blk < BLOCKS_PER_CHIP; blk++){
		for (int chip = 0; chip < CHIPS_PER_BUS; chip++){
			for (int bus = 0; bus < NUM_BUSES; bus++){
				eraseBlock(bus, chip, blk, waitIdleEraseTag());
			}
		}
	}

	while (true) {
		usleep(100);
		if (elapsed == 0) {
			elapsed=10000;
			device->debugDumpReq(0);
		}
		else {
			elapsed--;
		}
		if ( getNumErasesInFlight() == 0 ) break;
	}
//		device->debugDumpReq(0);
//		device->debugDumpReq(0);

//	//portalCacheFlush(dstAlloc, dstBuffer, dstAlloc_sz, 0);
//	printf( "TEST ERASED PAGES STARTED!\n" ); fflush(stdout);
//	//read back erased pages
//	for (int page = 0; page < MYPAGE; page++) {
//		for (int blk = 0; blk < BLOCKS_PER_CHIP; blk++){
//			for (int chip = 0; chip < CHIPS_PER_BUS; chip++){
//				for (int bus = 0; bus < NUM_BUSES; bus++){
//					readPage(bus, chip, blk, page, waitIdleReadBuffer());
//				}
//			}
//		}
//	}
//	
//	while (true) {
//		usleep(100);
//		if (elapsed == 0) {
//			elapsed=10000;
//			device->debugDumpReq(0);
//		}
//		else {
//			elapsed--;
//		}
//		if ( getNumReadsInFlight() == 0 ) break;
//	}
//
//	timespec start, now;
//	clock_gettime(CLOCK_REALTIME, & start);
//
//	//write pages
//	//FIXME: in old xbsv, simulatneous DMA reads using multiple readers cause kernel panic
//	//Issue each bus separately for now
//	printf( "TEST WRITE STARTED!\n" ); fflush(stdout);
//	for (int page = 0; page < MYPAGE; page++) {
//		for (int blk = 0; blk < BLOCKS_PER_CHIP; blk++){
//			for (int chip = 0; chip < CHIPS_PER_BUS; chip++){
//				for (int bus = 0; bus < NUM_BUSES; bus++){
//					int freeTag = waitIdleWriteBuffer();
//					//for (unsigned int w=0; w<FPAGE_SIZE/sizeof(unsigned int); w++) {
//					//	writeBuffers[freeTag][w] = hashAddrToData(bus, chip, blk, w);
//					//}
//					//send request
//					writePage(bus, chip, blk, page, freeTag);
//				}
//			}
//		}
//	} //each bus
//	
//	while (true) {
//		usleep(100);
//		if (elapsed == 0) {
//			elapsed=10000;
//			device->debugDumpReq(0);
//		}
//		else {
//			elapsed--;
//		}
//		if ( getNumWritesInFlight() == 0 ) break;
//	}
//	clock_gettime(CLOCK_REALTIME, & now);
//	fprintf(stderr, "LOG: finished writing from page! %f\n", timespec_diff_sec(start, now) );
//	fprintf(stderr, "SPEED: %f MB/s\n", (8192.0*NUM_BUSES*CHIPS_PER_BUS*BLOCKS_PER_CHIP*MYPAGE/1000000)/timespec_diff_sec(start,now));
//
//	clock_gettime(CLOCK_REALTIME, & start);
//	
//	printf( "TEST READ MULTI BUS STARTED!\n" ); fflush(stdout);
//	for (int repeat = 0; repeat < 1; repeat++){
//		for (int page = 0; page < MYPAGE; page++) {
//			for (int blk = 0; blk < BLOCKS_PER_CHIP; blk++){
//				for (int chip = 0; chip < CHIPS_PER_BUS; chip++){
//					for (int bus = 0; bus < NUM_BUSES; bus++){
//						readPage(bus, chip, blk, page, waitIdleReadBuffer());
//					}
//				}
//			}
//		}
//	}
//
//	while (true) {
//		usleep(100);
//		if (elapsed == 0) {
//			elapsed=10000;
//			device->debugDumpReq(0);
//		}
//		else {
//			elapsed--;
//		}
//		if ( getNumReadsInFlight() == 0 ) break;
//	}
//
//	device->debugDumpReq(0);
//
//	clock_gettime(CLOCK_REALTIME, & now);
//	fprintf(stderr, "LOG: finished reading from page! %f\n", timespec_diff_sec(start, now) );
//	fprintf(stderr, "SPEED: %f MB/s\n", (8192.0*NUM_BUSES*CHIPS_PER_BUS*BLOCKS_PER_CHIP*MYPAGE/1000000)/timespec_diff_sec(start,now));
//
//	sleep(2);
//	for ( int t = 0; t < NUM_TAGS; t++ ) {
//		for ( unsigned int i = 0; i < FPAGE_SIZE/sizeof(unsigned int); i++ ) {
//			fprintf(stderr,  "%d %d %x\n", t, i, writeBuffers[t][i] );
//		}
//	}
	printf("testPassed: %d\n",testPassed?1:0);
	if (testPassed==true) {
		fprintf(stderr, "LOG: TEST PASSED!\n");
	}
	else {
		fprintf(stderr, "LOG: **ERROR: TEST FAILED!\n");
	}

}
