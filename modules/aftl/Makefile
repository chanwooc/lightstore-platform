BUILD_DIR=build_dir
.PHONY: verilog test clean
.DEFAULT_GOAL := test

verilog:
	@mkdir -p verilog_build_dir
	bsc -bdir verilog_build_dir -vdir . -u -p +:dummy:../../lib:../../platform/flash_ctrl/common -verilog -show-schedule -aggressive-conditions -g mkAFTL128 AFTL.bsv

test:
	@mkdir -p build_dir sim_dir
ifdef SLC
	bsc -bdir build_dir -u -p +:dummy:../../lib:../../platform/flash_ctrl/common -D SIM_BRAM -D TWO_FLASH_CARDS -D SLC -sim -show-schedule -aggressive-conditions -g mkTestAFTL TestAFTL.bsv
else
	bsc -bdir build_dir -u -p +:dummy:../../lib:../../platform/flash_ctrl/common -D SIM_BRAM -D TWO_FLASH_CARDS -sim -show-schedule -aggressive-conditions -g mkTestAFTL TestAFTL.bsv
endif
	bsc -simdir sim_dir -u -p +:build_dir -sim -aggressive-conditions -show-schedule -e mkTestAFTL -o simTestAFTL

clean:
	rm -rf verilog_build_dir build_dir sim_dir simTest* *.sched *.v ../mk*.v ../*.sched
