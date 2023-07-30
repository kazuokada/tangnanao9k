`timescale 1ns / 1ps
// HDMI表示用のfifo書き込み
// 1280x720
// fifo 64byte x 4段
module psram_hdmi_top #(
    parameter HDMI_HSIZE = 1280,
    parameter HDMI_VSIZE = 720
    )
(
    input  wire         rst_n,      //
    input  wire         psramclk,   //82.5MHz
    input  wire         hdmiclk,    //74.25MHz
    input  wire         reg_clk,
    
    // PSRAM コマンドインターフェース
    output wire         psram_cmd,
    output wire         psram_cmd_en,
    output wire [22:2]  psram_addr,
    input wire [31:0]   psram_rdata,
    input wire          psram_rvalid,
    input wire          psram_cmd_ready,
    
    // wishbone i/f (for reg)
    input wire [11:0]   reg_mem_addr,
    input wire [31:0]   reg_mem_wdata,
    output reg [31:0]   reg_mem_rdata,
    input wire [3:0]    reg_mem_wstrb,
    input wire          reg_mem_valid,
    output wire         reg_mem_ready,

    // HDMI I/F
    output wire         out_rgb_de,
    output wire         out_rgb_vs,
    output wire         out_rgb_hs,
    output wire [7:0]   out_r,
    output wire [7:0]   out_g,
    output wire [7:0]   out_b,    
    // LED
    output wire         run_hdmi,
    output wire         vsync_flg,
    
    // dummy reg
    output wire [31:0]  DUMMY_REG
    
);

parameter DVI_H_BPORCH = 12'd220;
parameter DVI_H_ACTIVE = 12'd1280;
parameter DVI_H_FPORCH = 12'd110;
parameter DVI_H_SYNC   = 12'd40;
parameter DVI_H_POLAR  = 1'b1;
parameter DVI_V_BPORCH = 12'd20;
parameter DVI_V_ACTIVE = 12'd720;
parameter DVI_V_FPORCH = 12'd5;
parameter DVI_V_SYNC   = 12'd5;
parameter DVI_V_POLAR  = 1'b1;
// ---------------------------------
// 内部信号
// ---------------------------------
reg         rst_n_hdclk_sync1;
reg         rst_n_hdclk_sync2;
wire        rst_n_hdclk;

reg         rst_n_psclk_sync1;
reg         rst_n_psclk_sync2;
wire        rst_n_psclk;

wire        reg_r_ready;
wire        reg_w_ready;

// u_syncgen
wire        run_timinggen;
wire        syncgen_rgb_vs;
wire        syncgen_rgb_hs;
wire        syncgen_rgb_de;
wire        frame_last_pix;

// u_psram_hdmi_read

// reg i/f
//wire        start_hdmi;
//wire        stop_hdmi;
//wire [22:2] start_adrs; // read先頭アドレス(画像の先頭)
//wire        run_hdmi;

// disp_hdmi i/f
wire        fifo_empty;

// fifo i/f
wire [7:2]  fifo_adr;
wire        fifo_wen;
wire [31:0] fifo_wdata;
wire        fifo_rpt_update_hdclk;

// u_psram_hdmi_dsp
// reg i/f
//wire          start_hdmi;
//wire          stop_hdmi;
//wire          disp_run;
//wire          fifo_underrun;
//wire          clr_fifo_underrun;
//wire          VSYNC_flag;
//wire          clr_VSYNC_flag;

// disp_hdmi i/f
//wire          fifo_empty; // psramclk

// fifo i/f
wire [7:2]    fifo_radr;
wire          fifo_ren;
wire [31:0]   fifo_rdata;
//wire          fifo_rpt_update_hdclk;

// from timing generator
//wire          in_rgb_de;
//wire          in_rgb_vs;
//wire          in_rgb_hs;
//wire          in_frame_last_pix;

//wire          run_timinggen;
//wire         out_rgb_de;
//wire         out_rgb_vs;
//wire         out_rgb_hs;
//wire [7:0]    out_r;
//wire [7:0]    out_g;
//wire [7:0]    out_b;

assign reg_mem_ready = reg_r_ready & reg_w_ready ;
assign reg_w_ready = 1'b1;

// 各種レジスタ
reg         r_start;
reg         r_stop;
reg [22:0]  r_start_adrs;
reg [31:0]  r_dummy;
reg         clr_fifo_underrun;
reg         clr_VS_flag;
wire        VS_flag;
wire        fifo_underrun;
wire        disp_run;
wire        memif_run;
reg [47:0]  free_timer;

assign run_hdmi = disp_run; // for LED
assign vsync_flg = VS_flag;
assign DUMMY_REG = r_dummy;

//
// reset解除同期化
//
always@(posedge hdmiclk or negedge rst_n)
    if(!rst_n) begin
        rst_n_hdclk_sync1 <= 1'b0;
        rst_n_hdclk_sync2 <= 1'b0;
    end
    else begin
        rst_n_hdclk_sync1 <= rst_n;
        rst_n_hdclk_sync2 <= rst_n_hdclk_sync1;
    end
assign rst_n_hdclk = rst_n_hdclk_sync2;

always@(posedge psramclk or negedge rst_n)
    if(!rst_n) begin
        rst_n_psclk_sync1 <= 1'b0;
        rst_n_psclk_sync2 <= 1'b0;
    end
    else begin
        rst_n_psclk_sync1 <= rst_n;
        rst_n_psclk_sync2 <= rst_n_psclk_sync1;
    end
assign rst_n_psclk = rst_n_psclk_sync2;

// ------------------------------
// 各種ライト レジスタ
// reg if(wish bone)
// write enable(addres decode)
// ------------------------------
wire    start_wen;
wire    stop_wen;
wire    start_adrs_wen;
wire    clr_flag_wen;

assign start_wen = (reg_mem_addr==12'h000)&
                    reg_mem_valid&(reg_mem_wstrb[0])&reg_w_ready;
assign stop_wen = (reg_mem_addr==12'h004)&
                    reg_mem_valid&(reg_mem_wstrb[0])&reg_w_ready;
assign start_adrs_wen = (reg_mem_addr==12'h008)&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign clr_flag_wen = (reg_mem_addr==12'h010)&
                    reg_mem_valid&(reg_mem_wstrb[0])&reg_w_ready;
assign dummy_wen = (reg_mem_addr==12'h014)&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;

always@(negedge rst_n or posedge reg_clk)
    if(~rst_n)
        r_start <= 1'b0;
    else if(start_wen)
        r_start <= reg_mem_wdata[0];
always@(negedge rst_n or posedge reg_clk)
    if(~rst_n)
        r_stop <= 1'b0;
    else if(stop_wen)
        r_stop <= reg_mem_wdata[0];
always@(posedge reg_clk)
    if(start_adrs_wen)
        r_start_adrs <= reg_mem_wdata[22:0];
always@(negedge rst_n or posedge reg_clk)
    if(~rst_n)
        {clr_VS_flag,clr_fifo_underrun} <= 2'b00;
    else if(clr_flag_wen)
        {clr_VS_flag,clr_fifo_underrun} <= reg_mem_wdata[3:2];

always@(negedge rst_n or posedge reg_clk)
    if(~rst_n)
        r_dummy <= 32'h0000_0000;
    else if(dummy_wen)
        r_dummy <= reg_mem_wdata[31:0];

always@(negedge rst_n or posedge reg_clk)
    if(~rst_n)
        free_timer <= 48'h0000_0000_0000;
    else
        free_timer <= free_timer + 48'h0000_0000_0001;

// read busタイミング
wire read_bus = reg_mem_valid & (reg_mem_wstrb==4'h0);
wire read_start_bus;
wire read_stop_bus;
wire read_start_adrs_bus;
wire read_flag_bus;
wire read_timer0;
wire read_timer1;
assign read_start_bus = (reg_mem_addr==12'h000)&read_bus;
assign read_stop_bus = (reg_mem_addr==12'h004)&read_bus;
assign read_start_adrs_bus = (reg_mem_addr==12'h008)&read_bus;
assign read_flag_bus = (reg_mem_addr==12'h00c)&read_bus;
assign read_timer0 = (reg_mem_addr==12'h020)&read_bus;
assign read_timer1 = (reg_mem_addr==12'h024)&read_bus;
reg     RSTATE;
// ------------------------------------
// mem_r_ready (read側 wishbone ready)
// ------------------------------------
assign reg_r_ready = ~(read_bus & (~RSTATE));

// ------------------------------------
// RSTATE (read bus timing 後半サイクル)
// ------------------------------------
always@(negedge rst_n or posedge reg_clk)
    if(~rst_n)
        RSTATE <= 1'b0;
    else if(RSTATE)
        RSTATE <= 1'b0;
    else if(read_bus)
        RSTATE <= 1'b1;

// -------------------------------------
// bus
// reg_mem_rdata
// -------------------------------------
always@(posedge reg_clk)
    if(read_start_bus&(~RSTATE))
        reg_mem_rdata <= {28'h0000_000,3'b000,r_start};
    else if(read_stop_bus&(~RSTATE))
        reg_mem_rdata <= {28'h0000_000,3'b000,r_stop};
    else if(read_start_adrs_bus&(~RSTATE))
        reg_mem_rdata <= {9'h000,r_start_adrs};
    else if(read_flag_bus&(~RSTATE))
        reg_mem_rdata <= {28'h0000_000,
                            VS_flag,fifo_underrun,disp_run,memif_run};
    else if(read_timer0&(~RSTATE))
        reg_mem_rdata <= free_timer[31:0];
    else if(read_timer1&(~RSTATE))
        reg_mem_rdata <= free_timer[47:32];


syncgen u_syncgen (
    .rst_n(rst_n_hdclk),        // in
    .clk_pixel(hdmiclk),        // in
    .run_timinggen(run_timinggen),  // in
    .rgb_vs(syncgen_rgb_vs),    // out
    .rgb_hs(syncgen_rgb_hs),    // out
    .rgb_de(syncgen_rgb_de),    // out
    .frame_last_pix(frame_last_pix) // out
);

psram_hdmi_read
#(
//   .HDMI_HSIZE(DVI_H_BPORCH + DVI_H_ACTIVE + DVI_H_FPORCH + DVI_H_SYNC),
//   .HDMI_VSIZE(DVI_V_BPORCH + DVI_V_ACTIVE + DVI_V_FPORCH + DVI_V_SYNC)
    .TCMD_cyc(2),   // tcmd_cycはアービタ側で保障。先出reqするために値を小さく
    .HDMI_HSIZE(DVI_H_ACTIVE),
    .HDMI_VSIZE(DVI_V_ACTIVE)
) u_psram_hdmi_read
(
    .rst_n_psclk(rst_n_psclk),  //in  // psramclk同期化済み
    .psramclk(psramclk),        // in //82.5MHz
    
    // PSRAM コマンドインターフェース
    .psram_cmd(psram_cmd),          // out
    .psram_cmd_en(psram_cmd_en),    // out
    .psram_addr(psram_addr[22:2]),  // out
    .psram_rdata(psram_rdata),      // in
    .psram_rvalid(psram_rvalid),    // in
    .psram_cmd_ready(psram_cmd_ready), // in
    
    // reg i/f
    .start_hdmi(r_start),       // in
    .stop_hdmi(r_stop),         // in
    .start_adrs(r_start_adrs),  // in // read先頭アドレス(画像の先頭)
    .run_hdmi(memif_run),       // out
    
    // disp_hdmi i/f
    .fifo_empty(fifo_empty),    // out
    
    // fifo i/f
    .fifo_adr(fifo_adr),        // out
    .fifo_wen(fifo_wen),        // out
    .fifo_wdata(fifo_wdata),    // out
    .fifo_rpt_update_hdclk(fifo_rpt_update_hdclk)   // in
);

psram_hdmi_disp u_psram_hdmi_disp (
    .rst_n_hdclk(rst_n_hdclk),  // in // hdmiclk同期化済み
    .hdmiclk(hdmiclk),          // in //74.25MHz

    // reg i/f
    .start_hdmi(r_start),       // in
    .stop_hdmi(r_stop),         // in
    .disp_run(disp_run),        // out
    .fifo_underrun(fifo_underrun),          // out
    .clr_fifo_underrun(clr_fifo_underrun),  // in
    .VSYNC_flag(VS_flag),       // out
    .clr_VSYNC_flag(clr_VS_flag),           // in
    
    // disp_hdmi i/f
    .fifo_empty(fifo_empty),    // in   // psramclk
    
    // fifo i/f
    .fifo_radr(fifo_radr),      // out
    .fifo_ren(fifo_ren),        // out
    .fifo_rdata(fifo_rdata),    // in
    .fifo_rpt_update_hdclk(fifo_rpt_update_hdclk),  // out
    
    // from timing generator
    .in_rgb_de(syncgen_rgb_de), // in
    .in_rgb_vs(syncgen_rgb_vs), // in
    .in_rgb_hs(syncgen_rgb_hs), // in
    .in_frame_last_pix(frame_last_pix), // in
    
    .run_timinggen(run_timinggen),      // out
    .out_rgb_de(out_rgb_de),    // out
    .out_rgb_vs(out_rgb_vs),    // out
    .out_rgb_hs(out_rgb_hs),    // out
    .out_r(out_r),              // out
    .out_g(out_g),              // out
    .out_b(out_b)               // out

);

// fifo dual port mem
dual_port_mem  #(
            .NUM_COL(4),
            .COL_WIDTH(8),
            .ADDR_WIDTH(6)
            ) u_dual_port_mem (
        // psram read ch
        .clkA(psramclk),         // in
        .enaA(fifo_wen),         // in
        .weA({4{fifo_wen}}),     // in
        .addrA(fifo_adr),        // in
        .dinA(fifo_wdata),       // in
        .doutA(),                // out
       
        .clkB(hdmiclk),          // in
        .enaB(fifo_ren),         // in
        .weB(4'h0),              // in
        .addrB(fifo_radr),       // in
        .dinB(32'h0),            // in
        .doutB(fifo_rdata)       // out
);

endmodule
