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
#include "dmaManager.h"

// Connectal HW-SW interface
#include "KtIndication.h"
#include "KtRequest.h"

#define KEYTABLE_SIZE (8192)

KtRequestProxy *device;
sem_t sem;

int num_merged=-1;

int lowKtAlloc, highKtAlloc, mergedKtAlloc;
unsigned int ref_lowKtAlloc, ref_highKtAlloc, ref_mergedKtAlloc;
unsigned char *lowKtBuf, *highKtBuf, *mergedKtBuf;

class KtIndication: public KtIndicationWrapper {
	public:
		KtIndication(unsigned int id) : KtIndicationWrapper(id){}

		virtual void mergeDone(unsigned int numMergedKt, uint64_t counter) {
			fprintf(stderr, "mergeDone: %u %" PRIu64 "\n", numMergedKt, counter);
			num_merged = (int)numMergedKt;
			fflush(stderr);
			sem_post(&sem);
		}

		virtual void echoBack(unsigned int magic) {
			fprintf(stderr, "magic returned: %u\n", magic);
			fflush(stderr);
		}
};

int main(int argc, const char **argv)
{
	sem_init(&sem, 0, 0);
	FILE *h_fp = fopen("h_level.bin", "rb");
	FILE *l_fp = fopen("l_level.bin", "rb");

	if(h_fp == NULL) {
		fprintf(stderr, "h_level.bin missing\n");
		return -1;
	}

	if(l_fp == NULL) {
		fprintf(stderr, "l_level.bin missing\n");
		fclose(h_fp);
		return -1;
	}

	struct stat stat_buf;
	fstat(fileno(h_fp), &stat_buf);
	size_t h_size = (size_t)stat_buf.st_size;

	if(h_size%8192 != 0) {
		fprintf(stderr, "h_level.bin size not multiple of 8192\n");
		fclose(h_fp);
		fclose(l_fp);
		return -1;
	}

	fstat(fileno(l_fp), &stat_buf);
	size_t l_size = (size_t)stat_buf.st_size;

	if(l_size%8192 != 0) {
		fprintf(stderr, "l_level.bin size not multiple of 8192\n");
		fclose(h_fp);
		fclose(l_fp);
		return -1;
	}


	// Merger Vars
	size_t highKtAlloc_sz = ((h_size-1)/8192/128+1)*128*8192; // 1MB unit allocation
	size_t lowKtAlloc_sz = ((l_size-1)/8192/128+1)*128*8192; 
	size_t mergedKtAlloc_sz = highKtAlloc_sz+lowKtAlloc_sz;

	fprintf(stderr, "File open successful.. h_level.bin(%zd) l_level.bin(%zd)\n", h_size, l_size);

	fprintf(stderr, "Initializing Connectal & DMA...\n");

	// Device initialization
	device = new KtRequestProxy(IfcNames_KtRequestS2H);
	KtIndication deviceIndication(IfcNames_KtIndicationH2S);
	DmaManager *dma = platformInit();

	
	// Memory-allocation for DMA
	highKtAlloc = portalAlloc(highKtAlloc_sz, 0);
	lowKtAlloc = portalAlloc(lowKtAlloc_sz, 0);
	mergedKtAlloc = portalAlloc(mergedKtAlloc_sz, 0);

	highKtBuf = (unsigned char*)portalMmap(highKtAlloc, highKtAlloc_sz);
	lowKtBuf = (unsigned char*)portalMmap(lowKtAlloc, lowKtAlloc_sz);
	mergedKtBuf = (unsigned char*)portalMmap(mergedKtAlloc, mergedKtAlloc_sz);

	fprintf(stderr, "highKtAlloc   = %x\n", highKtAlloc); 
	fprintf(stderr, "lowKtAlloc    = %x\n", lowKtAlloc); 
	fprintf(stderr, "mergedKtAlloc = %x\n", mergedKtAlloc); 

	// Memory-mapping for DMA
	portalCacheFlush(highKtAlloc, highKtBuf, highKtAlloc_sz, 1);
	portalCacheFlush(lowKtAlloc, lowKtBuf, lowKtAlloc_sz, 1);
	portalCacheFlush(mergedKtAlloc, mergedKtBuf, mergedKtAlloc_sz, 1);

	ref_highKtAlloc = dma->reference(highKtAlloc);
	ref_lowKtAlloc = dma->reference(lowKtAlloc);
	ref_mergedKtAlloc = dma->reference(mergedKtAlloc);

	fprintf(stderr, "ref_highKtAlloc   = %x\n", ref_highKtAlloc); 
	fprintf(stderr, "ref_lowKtAlloc    = %x\n", ref_lowKtAlloc); 
	fprintf(stderr, "ref_mergedKtAlloc = %x\n", ref_mergedKtAlloc); 

	device->setKtHighRef(ref_highKtAlloc);
	device->setKtLowRef(ref_lowKtAlloc);
	device->setResultRef(ref_mergedKtAlloc);

	long actualFrequency=0;
	long requestedFrequency=1e9/MainClockPeriod;
	int status = setClockFrequency(0, requestedFrequency, &actualFrequency);
	fprintf(stderr, "HW Operating Freq - Requested: %5.2f, Actual: %5.2f, status=%d\n"
			,(double)requestedFrequency*1.0e-6
			,(double)actualFrequency*1.0e-6,status);

	fprintf(stderr, "Done initializing Hardware & DMA!\n" ); 
	fflush(stderr);

	fprintf(stderr, "Echo Back Testing...\n" );
	fflush(stderr);

	device->echoSecret(0);   // echo-back debug message
	sleep(1);

	if(fread(highKtBuf, h_size, 1, h_fp) != 1) {
		fprintf(stderr, "h_level.bin read failed\n");
		fclose(h_fp);
		fclose(l_fp);
		return -1;
	}

	if(fread(lowKtBuf, l_size, 1, l_fp) != 1) {
		fprintf(stderr, "l_level.bin read failed\n");
		fclose(h_fp);
		fclose(l_fp);
		return -1;
	}

	fclose(h_fp);
	fclose(l_fp);

	fprintf(stderr, "Binary Loaded on Host!\n" );
	device->runMerge( h_size/8192, l_size/8192 );

	fprintf(stderr, "Start!\n" );

	fflush(stderr);

	sem_wait(&sem);


	FILE *fp = fopen("hw-result.bin", "wb");
	if (fp == NULL) {
		fprintf(stderr, "result.bin open failed\n");
		return -1;
	}

	if (fwrite(mergedKtBuf, (size_t)num_merged*8192, 1, fp) != 1) {
		fprintf(stderr, "result.bin write failed\n");
		fclose(fp);
		return -1;
	}
	fclose(fp);

	fprintf(stderr, "result.bin dumped!\n");

	return 0;
}
