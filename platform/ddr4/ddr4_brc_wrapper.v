module ddr4_brc_wrapper
  (
   input               sys_rst,

   // input               c0_sys_clk_p,
   // input               c0_sys_clk_n,
   input               c0_sys_clk_i,



   output              c0_ddr4_act_n,
   output [16:0]       c0_ddr4_adr,
   output [1:0]        c0_ddr4_ba,
   output [0:0]        c0_ddr4_bg,
   output [0:0]        c0_ddr4_cke,
   output [0:0]        c0_ddr4_odt,
   output [0:0]        c0_ddr4_cs_n,
   output [0:0]        c0_ddr4_ck_t,
   output [0:0]        c0_ddr4_ck_c,
   output              c0_ddr4_reset_n,
   inout [9:0]         c0_ddr4_dm_dbi_n,
   inout [79:0]        c0_ddr4_dq,
   inout [9:0]         c0_ddr4_dqs_c,
   inout [9:0]         c0_ddr4_dqs_t,

   output              c0_init_calib_complete,
   output              c0_ddr4_ui_clk,
   output              c0_ddr4_ui_clk_sync_rst,
   output              dbg_clk,

   // user interface ports
(* mark_debug = "true" *)   input [27:0]        c0_ddr4_app_addr,
(* mark_debug = "true" *)   input [2:0]         c0_ddr4_app_cmd,
(* mark_debug = "true" *)   input               c0_ddr4_app_en,
(* mark_debug = "true" *)   input               c0_ddr4_app_hi_pri,
(* mark_debug = "true" *)   input [639:0]       c0_ddr4_app_wdf_data,
(* mark_debug = "true" *)   input               c0_ddr4_app_wdf_end,
(* mark_debug = "true" *)   input [79:0]        c0_ddr4_app_wdf_mask,
(* mark_debug = "true" *)   input               c0_ddr4_app_wdf_wren,

(* mark_debug = "true" *)   output [639:0]      c0_ddr4_app_rd_data,
(* mark_debug = "true" *)   output              c0_ddr4_app_rd_data_end,
(* mark_debug = "true" *)   output              c0_ddr4_app_rd_data_valid,
(* mark_debug = "true" *)   output              c0_ddr4_app_rdy,
(* mark_debug = "true" *)   output              c0_ddr4_app_wdf_rdy,
   // Debug Port
   output wire [511:0] dbg_bus
   );

   ddr4_brc
     inst 
       (
        .sys_rst           (~sys_rst),

        // .c0_sys_clk_p                   (c0_sys_clk_p),
        // .c0_sys_clk_n                   (c0_sys_clk_n),
        .c0_sys_clk_i                   (c0_sys_clk_i),



        .c0_ddr4_act_n          (c0_ddr4_act_n),
        .c0_ddr4_adr            (c0_ddr4_adr),
        .c0_ddr4_ba             (c0_ddr4_ba),
        .c0_ddr4_bg             (c0_ddr4_bg),
        .c0_ddr4_cke            (c0_ddr4_cke),
        .c0_ddr4_odt            (c0_ddr4_odt),
        .c0_ddr4_cs_n           (c0_ddr4_cs_n),
        .c0_ddr4_ck_t           (c0_ddr4_ck_t),
        .c0_ddr4_ck_c           (c0_ddr4_ck_c),
        .c0_ddr4_reset_n        (c0_ddr4_reset_n),
        .c0_ddr4_dm_dbi_n       (c0_ddr4_dm_dbi_n),
        .c0_ddr4_dq             (c0_ddr4_dq),
        .c0_ddr4_dqs_c          (c0_ddr4_dqs_c),
        .c0_ddr4_dqs_t          (c0_ddr4_dqs_t),
        
        .c0_init_calib_complete (c0_init_calib_complete),
        .c0_ddr4_ui_clk                (c0_ddr4_ui_clk),
        .c0_ddr4_ui_clk_sync_rst       (c0_ddr4_ui_clk_sync_rst),
        .dbg_clk                                    (dbg_clk),
        
        .c0_ddr4_app_addr              (c0_ddr4_app_addr),
        .c0_ddr4_app_cmd               (c0_ddr4_app_cmd),
        .c0_ddr4_app_en                (c0_ddr4_app_en),
        .c0_ddr4_app_hi_pri            (c0_ddr4_app_hi_pri),
        .c0_ddr4_app_wdf_data          (c0_ddr4_app_wdf_data),
        .c0_ddr4_app_wdf_end           (c0_ddr4_app_wdf_end),
        .c0_ddr4_app_wdf_mask          (c0_ddr4_app_wdf_mask),
        .c0_ddr4_app_wdf_wren          (c0_ddr4_app_wdf_wren),
        
        .c0_ddr4_app_rd_data           (c0_ddr4_app_rd_data),
        .c0_ddr4_app_rd_data_end       (c0_ddr4_app_rd_data_end),
        .c0_ddr4_app_rd_data_valid     (c0_ddr4_app_rd_data_valid),
        .c0_ddr4_app_rdy               (c0_ddr4_app_rdy),
        .c0_ddr4_app_wdf_rdy           (c0_ddr4_app_wdf_rdy),
        // Debug Port
        .dbg_bus               (dbg_bus) 
        );
endmodule

