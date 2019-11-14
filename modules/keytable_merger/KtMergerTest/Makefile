BUILD_DIR=build_dir
.PHONY: keytable test clean

keytable:
	@mkdir -p build_dir
	bsc -bdir build_dir -vdir . -u -p +:..:../../../lib:../../../platform/flash_ctrl/common -verilog -show-schedule -aggressive-conditions -g mkKeytableMerger ../KeytableMerger.bsv

test:
	@mkdir -p build_dir sim_dir
	bsc -bdir build_dir -u -p +:..:../../../lib:../../../platform/flash_ctrl/common -sim -show-schedule -aggressive-conditions -g mkTest TestSuite.bsv
	bsc -simdir sim_dir -u -p +:..:build_dir -sim -aggressive-conditions -show-schedule -e mkTest -o simTest

clean:
	rm -rf build_dir sim_dir simTest simTest.so *.sched *.v ../mk*.v ../*.sched
