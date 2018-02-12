
////////////////////////////////////////////////////////////////////////////////
/// IBUFDS_GTE4
////////////////////////////////////////////////////////////////////////////////
interface GTE4ClockGenIfc;
   interface Clock gen_clk;
   interface Clock gen_clk_div2;
endinterface

import "BVI" IBUFDS_GTE4 =
module vMkClockIBUFDS_GTE4#(Bool enable, Clock clk_p, Clock clk_n)(GTE4ClockGenIfc);
   default_clock no_clock;
   default_reset no_reset;

   input_clock clk_p(I)  = clk_p;
   input_clock clk_n(IB) = clk_n;

   port CEB = pack(!enable);

   output_clock gen_clk(O);
   output_clock gen_clk_div2(ODIV2);
   
   path(I,  O);
   path(IB, O);
   path(I,  ODIV2);
   path(IB, ODIV2);

   same_family(clk_p, gen_clk);
endmodule: vMkClockIBUFDS_GTE4

module mkClockIBUFDS_GTE4#(Bool enable, Clock clk_p, Clock clk_n)(Clock);
   let _m <- vMkClockIBUFDS_GTE4(enable, clk_p, clk_n);
   return _m.gen_clk;
endmodule: mkClockIBUFDS_GTE4
