#include <stdio.h>
#include <sys/mman.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <monkit.h>
#include <semaphore.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include <time.h>

// Connectal DMA interface
// #include "dmaManager.h"

// Connectal HW-SW interface
#include "AftlIndication.h"
#include "AftlRequest.h"

AftlRequestProxy *device;
pthread_mutex_t aftlReqMutex;

class AftlIndication: public AftlIndicationWrapper {
	public:
		void respSuccess(AmfFlashRequest resp) {
			fprintf(stderr, "RespOK tag=%u cmd=%u card/bus/chip/blk/page=%u/%u/%u/%u/%u\n", resp.tag, (int)resp.cmd, resp.card, resp.bus, resp.chip, resp.block, resp.page);
		}

		void respFailed(AmfRequest resp) {
			fprintf(stderr, "RespFAIL tag=%u cmd=%u lpa=%u\n", resp.tag, (unsigned int)resp.cmd, resp.lpa);
		}

		void respReadMapping(uint8_t allocated, uint16_t block_num) {
			fprintf(stderr, "respReadMapping: allocated?%u, blk=%u\n", allocated, block_num);
		}

		void respReadBlkInfo(const uint16_t* blkinfo_vec ) {
			fprintf(stderr, "respReadBlkInfo:\n");
			for(int i =0; i<8; i++) {
				fprintf(stderr, "[%d] %d %d ", i, blkinfo_vec[i] >> 14, blkinfo_vec[i] & ( (1<<14)-1 ) );
			}
			fprintf(stderr, "\n");
		}

		AftlIndication(unsigned int id, PortalTransportFunctions *transport = 0, void *param = 0, PortalPoller *poller = 0) 
			: AftlIndicationWrapper(id, transport, param, poller) {}
};


int main(int argc, const char **argv)
{
	pthread_mutex_init(&aftlReqMutex, NULL);

	fprintf(stderr, "Initializing Connectal & DMA...\n");

	// Device initialization
	device = new AftlRequestProxy(IfcNames_AftlRequestS2H);
	AftlIndication deviceIndication(IfcNames_AftlIndicationH2S);

	// AmfRequest
	//    cmd: AmfREAD AmfWRITE AmfERASE
	//    tag: 0~127
	//    lpa: 27-bit number
	AmfRequest myreq;

//	myreq.cmd = AmfREAD;
//	myreq.tag = 0;
//	for (unsigned int i = 0; i < 128; i++) {
//		myreq.lpa = i;
//		device->makeReq(myreq);
//	}

	// Upper 2-bit: 0b00: FREE_BLK 0b01: USED_BLK (ALLOCATED) 0b10: BAD_BLK 0b11: DIRTY_BLK (not used)
	uint16_t newlist[8];
	for (int i =0; i<8; i++) newlist[i] = 1024;
	newlist[4] = 4;
	newlist[5] = 9;

	newlist[4] = newlist[4] | (2 << 14);

	device->updateBlkInfo(0, newlist);
   
	device->readMapping(0);
	device->readBlkInfo(0);

	myreq.cmd = AmfWRITE;
	for (unsigned int i = 0; i < 64; i++) {
		myreq.lpa = i;
		device->makeReq(myreq);
	}

	sleep(1);
	device->readMapping(0);
	device->readBlkInfo(0);

	myreq.cmd = AmfERASE;
	myreq.lpa = 0;
	device->makeReq(myreq);

	sleep(1);
	device->readMapping(0);
	device->readBlkInfo(0);
//	myreq.cmd = AmfREAD;
//	for (unsigned int i = 0; i < 128; i++) {
//		myreq.lpa = i;
//		device->makeReq(myreq);
//	}
	sleep(1);

}
