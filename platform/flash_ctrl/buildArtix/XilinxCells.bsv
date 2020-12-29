import DefaultValue      ::*;
import Clocks            ::*;

interface ClockGenIfc;
	interface Clock gen_clk;
endinterface

import "BVI" BUFG =
module vMkClockBUFG(ClockGenIfc);
   default_clock clk(I, (*unused*)GATE);
   default_reset no_reset;

   path(I, O);

   output_clock gen_clk(O);

   same_family(clk, gen_clk);
endmodule: vMkClockBUFG

module mkClockBUFG(Clock);
   let _m <- vMkClockBUFG;
   return _m.gen_clk;
endmodule: mkClockBUFG

typedef struct {
   String      clkcm_cfg;
   String      clkrcv_trst;
   Bit#(2)     clkswing_cfg;
} IBUFDS_GTE2Params deriving (Bits, Eq);

instance DefaultValue#(IBUFDS_GTE2Params);
   defaultValue = IBUFDS_GTE2Params {
      clkcm_cfg:          "TRUE",
      clkrcv_trst:        "TRUE",
      clkswing_cfg:       2'b11
      };
endinstance

interface GTE2ClockGenIfc;
   interface Clock gen_clk;
   interface Clock gen_clk_div2;
endinterface

import "BVI" IBUFDS_GTE2 =
module vMkClockIBUFDS_GTE2#(IBUFDS_GTE2Params params, Bool enable, Clock clk_p, Clock clk_n)(GTE2ClockGenIfc);
   default_clock no_clock;
   default_reset no_reset;

   input_clock clk_p(I)  = clk_p;
   input_clock clk_n(IB) = clk_n;

   port CEB = pack(!enable);

   output_clock gen_clk(O);
   output_clock gen_clk_div2(ODIV2);

   parameter CLKCM_CFG      = params.clkcm_cfg;
   parameter CLKRCV_TRST    = params.clkrcv_trst;
   parameter CLKSWING_CFG   = (Bit#(2))'(params.clkswing_cfg);

   path(I,  O);
   path(IB, O);
   path(I,  ODIV2);
   path(IB, ODIV2);

   same_family(clk_p, gen_clk);
endmodule: vMkClockIBUFDS_GTE2

module mkClockIBUFDS_GTE2#(IBUFDS_GTE2Params params, Bool enable, Clock clk_p, Clock clk_n)(Clock);
   let _m <- vMkClockIBUFDS_GTE2(params, enable, clk_p, clk_n);
   return _m.gen_clk;
endmodule: mkClockIBUFDS_GTE2
