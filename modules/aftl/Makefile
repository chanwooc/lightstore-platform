BUILD_DIR=build_dir
.PHONY: all test clean

all:
	@mkdir -p build_dir
	bsc -bdir build_dir -vdir . -u -p +:../../lib:../../platform/flash_ctrl/common -verilog -show-schedule -aggressive-conditions -g mkAFTL2 AFTL.bsv

test:
	@mkdir -p build_dir sim_dir
	bsc -bdir build_dir -u -p +:../../lib:../../platform/flash_ctrl/common -D SIM_BRAM -D FLASH_FMC2 -sim -show-schedule -aggressive-conditions -g mkTestAFTL TestAFTL.bsv
	bsc -simdir sim_dir -u -p +:build_dir -sim -aggressive-conditions -show-schedule -e mkTestAFTL -o simTestAFTL

clean:
	rm -rf build_dir sim_dir simTest* *.sched *.v ../mk*.v ../*.sched
