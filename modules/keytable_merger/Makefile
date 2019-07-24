BUILD_DIR=build_dir
.PHONY: keytable test clean

keytable:
	@mkdir -p build_dir
	touch ConnectalProjectConfig.bsv
	bsc -bdir build_dir -u -p +:../../lib:../../modules/flash_ctrl/common -verilog -show-schedule -aggressive-conditions -g mkMergeKeytable KeytableMerger.bsv
	rm -f ConnectalProjectConfig.bsv

test:
	@mkdir -p build_dir sim_dir
	touch ConnectalProjectConfig.bsv
	bsc -bdir build_dir -u -p +:../../lib:../../modules/flash_ctrl/common -sim -show-schedule -aggressive-conditions -g mkTest TestSuite.bsv
	bsc -simdir sim_dir -u -p +:build_dir:../../lib:../../modules/flash_ctrl/common -sim -aggressive-conditions -show-schedule -e mkTest -o simTest
	rm -f ConnectalProjectConfig.bsv

clean:
	rm -rf build_dir sim_dir simTest simTest.so *.sched *.v ConnectalProjectConfig.bsv
