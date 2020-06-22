// Courtesy of Shuotao
#include <sys/time.h>
#include <iostream>

#include "Ddr4PerfIndication.h"
#include "Ddr4PerfRequest.h"

#define CL_SZ 80

sem_t write_sem;
sem_t read_sem;

unsigned long numCL = 0;

class Ddr4PerfIndication : public Ddr4PerfIndicationWrapper{
public:
	virtual void writeDone(uint32_t cycles_0, uint32_t cycles_1){
		uint32_t cycles = (cycles_0>cycles_1) ? cycles_0 : cycles_1;
		fprintf(stderr, "Write Benchmark done in %d cycles(%d vs %d)\n", cycles, cycles_0, cycles_1);
		fprintf(stderr, "Write Benchmark BW = %.02lfGB/s\n", (2*numCL*CL_SZ)/(4.0*cycles));
		sem_post(&write_sem);
	}

	virtual void readDone(uint32_t cycles_0, uint32_t missMatch_0, uint32_t cycles_1, uint32_t missMatch_1){
		uint32_t cycles = (cycles_0>cycles_1) ? cycles_0 : cycles_1;
		fprintf(stderr, "Read Benchmark done in %d cycles(%d vs %d), missMatch = %d (%d + %d)\n", cycles, cycles_0, cycles_1, missMatch_0 + missMatch_1, missMatch_0, missMatch_1);
		fprintf(stderr, "Read Benchmark BW = %.02lfGB/s\n", (2*numCL*CL_SZ)/(4.0*cycles));
		sem_post(&read_sem);
	}

	Ddr4PerfIndication(unsigned int id) : Ddr4PerfIndicationWrapper(id){}
};

int main(int argc, const char **argv){
	Ddr4PerfRequestProxy *device = new Ddr4PerfRequestProxy(IfcNames_Ddr4PerfRequestS2H);
	Ddr4PerfIndication testIndication(IfcNames_Ddr4PerfIndicationH2S);

	if(sem_init(&write_sem, 1, 0)){
		fprintf(stderr, "failed to init write_sem\n");
		return -1;
	}

	if(sem_init(&read_sem, 1, 0)){
		fprintf(stderr, "failed to init read_sem\n");
		 return -1;
	}

	int stride;
	std::cout << "input your stride width: ";
	std::cin >> stride;

#ifdef SIMULATION
	numCL = 1UL << (10-stride);
	fprintf(stderr, "SIMULATION STARTS\n");
#else
	numCL = 1UL << (25-stride);
	fprintf(stderr, "FPGA STARTS\n");
#endif

	device->startWriteDram(numCL, stride);
	sem_wait(&write_sem);

	device->startReadDram(numCL, stride);
	sem_wait(&read_sem);
}
