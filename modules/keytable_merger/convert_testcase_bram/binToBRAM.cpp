#include <cstdio>

int main()
{
	const char* file_names[] = {"./h_level.bin", "./l_level.bin", "./result.bin"};
	const char* o_file_names[] = {"./h_level.bram", "./l_level.bram", "./result.bram"};
	int f_size[] = {52, 52, 74};

	for (int ii = 0; ii < 3; ii++) {
		int binarySize = f_size[ii] * 8192;

		FILE *fpBin = fopen(file_names[ii], "rb");
		if (fpBin == NULL) {
			printf("Cannot open bin file\n");
			return -1;
		}

		FILE *fpBram = fopen(o_file_names[ii], "w");
		if (fpBram == NULL) {
			printf("Cannot create output.bram\n");
			fclose(fpBin);
			return -1;
		}

		int num4Bs = binarySize / 4;
		unsigned int* buf4B = new unsigned int[num4Bs];
		
		int readElem = fread( buf4B, 4, num4Bs, fpBin );

		if (readElem != num4Bs) {
			printf("Expected 4B reads: %d, Real 4B reads: %d, BIN size: %d\n", num4Bs, readElem, binarySize);
		}

		int numWords = binarySize / 16;
		
		for (int ii=0; ii < numWords; ii++) {
			fprintf(fpBram,"%08x%08x%08x%08x\n", buf4B[4*ii+3], buf4B[4*ii+2], buf4B[4*ii+1], buf4B[4*ii]);
		}

		fclose(fpBin);
		fclose(fpBram);
	}

	return 0;
}
