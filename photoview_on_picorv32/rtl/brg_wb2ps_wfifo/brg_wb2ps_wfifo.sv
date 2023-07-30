`timescale 1ns/1ps
// wishbone → PSRAM バスブリッジ
// 
// 64burst(64byte) 転送
// data幅 32bit
// writeのみ
// fifo型
// 64byte x4

module brd_wb2ps_wfifo (
    input RST,
    input cpuclk,       // wishbone clk 
    // wishbone
    // reg i/f
    // fifo制御用
    input wire [11:0]   reg_mem_addr,
    input wire [31:0]   reg_mem_wdata,
    output reg [31:0]   reg_mem_rdata,
    input wire [3:0]    reg_mem_wstrb,
    input wire          reg_mem_valid,
    output wire         reg_mem_ready,

    // PSRAM i/f
    // psramclk domain
    // fifo側のPSRAM I/F
    input wire          half_psramclk,      // 83MHz clk
    output wire         cmd_fifo,           // output cmd
    output wire         cmd_en_fifo,        // output cmd_en
    output wire [22:0]  addr_fifo,
    output wire [31:0]  wr_data_fifo,
    output wire [3:0]   data_mask_fifo,
    input wire          cmd_ready_fifo
    
    );

// ---------------------------------
// 結線 wire 宣言
// ---------------------------------
wire    psramclk = half_psramclk;
wire    psclk = half_psramclk;
wire    WSHRST;
wire    PSRST;
reg     RST_cpuclk_sync1;
reg     RST_cpuclk_sync2;
reg     RST_psramclk_sync1;
reg     RST_psramclk_sync2;


// 動作速度観測用タイマー
// for debug
reg [47:0]  free_timer;

// register
reg [31:0]  fifo_wadrs;
reg [31:0]  fifo_warea;
reg [31:0]  fifo_wdata;
reg         fifo_wdata_wen2;
reg         fifo_startp;
reg         fifo_endp;
reg         fifo_reg_eflag;
wire        fifo_almost_full;
wire        fifo_run;
wire        fifo_run_endp;

wire        reg_r_ready;
wire        reg_w_ready;

// 内部レジスタ wen
wire        fifo_wadrs_wen;
wire        fifo_warea_wen;
wire        fifo_wdata_wen;
wire        fifo_ctl;


wire        read_freetimer0;
wire        read_freetimer1;
wire        read_fifo_wadrs;
wire        read_fifo_warea;
wire        read_fifo_ctl;

reg         RSTATE;

assign reg_mem_ready = reg_r_ready & reg_w_ready ;
assign reg_w_ready = ~fifo_almost_full;

// ---------------------------------
// 各種ライト レジスタ
// ---------------------------------
assign fifo_wadrs_wen = (reg_mem_addr[11:2]==(12'h030>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign fifo_warea_wen = (reg_mem_addr[11:2]==(12'h034>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign fifo_wdata_wen = (reg_mem_addr[11:2]==(12'h038>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
assign fifo_ctl = (reg_mem_addr[11:2]==(12'h03c>>2))&
                    reg_mem_valid&(|reg_mem_wstrb)&reg_w_ready;
                     
// fifo制御
always@(posedge cpuclk)
    if(fifo_wadrs_wen)
        fifo_wadrs <= reg_mem_wdata;
always@(posedge cpuclk)
    if(fifo_warea_wen)
        fifo_warea <= reg_mem_wdata;
always@(posedge cpuclk)
    if(fifo_wdata_wen)
        fifo_wdata <= reg_mem_wdata;
always@(posedge cpuclk)
    fifo_wdata_wen2 <= fifo_wdata_wen;
    
// fifo_startp/endp 1shot
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_startp <= 1'b0;
    else if(fifo_startp)
        fifo_startp <= 1'b0;
    else if(fifo_ctl) begin
        if(reg_mem_wdata[0])
            fifo_startp <= 1'b1;
    end
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_endp <= 1'b0;
    else if(fifo_endp)
        fifo_endp <= 1'b0;
    else if(fifo_ctl) begin
        if(reg_mem_wdata[1])
            fifo_endp <= 1'b1;
    end

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        fifo_reg_eflag <= 1'b0;
    else if(fifo_run_endp)
        fifo_reg_eflag <= 1'b1;
    else if(fifo_ctl&reg_mem_wdata[8])  // 1write clear
        fifo_reg_eflag <= 1'b0;

// read busタイミング
wire read_bus = reg_mem_valid & (reg_mem_wstrb==4'h0);
assign read_freetimer0 = (reg_mem_addr[11:2]==(12'h010>>2))&read_bus;
assign read_freetimer1 = (reg_mem_addr[11:2]==(12'h014>>2))&read_bus;
assign read_fifo_wadrs = (reg_mem_addr[11:2]==(12'h030>>2))&read_bus;
assign read_fifo_warea = (reg_mem_addr[11:2]==(12'h034>>2))&read_bus;
assign read_fifo_ctl = (reg_mem_addr[11:2]==(12'h03c>>2))&read_bus;

// ------------------------------------
// mem_r_ready (read側 wishbone ready)
// ------------------------------------
assign reg_r_ready = ~(read_bus & (~RSTATE));

// ------------------------------------
// RSTATE (read bus timing 後半サイクル)
// ------------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        RSTATE <= 1'b0;
    else if(RSTATE)
        RSTATE <= 1'b0;
    else if(read_bus)
        RSTATE <= 1'b1;
// -------------------------------------
// bus
// reg_mem_rdata
// -------------------------------------
always@(posedge cpuclk)
    if(read_freetimer0&(~RSTATE))
        reg_mem_rdata <= free_timer[31:0];
    else if(read_freetimer1&(~RSTATE))
        reg_mem_rdata <= free_timer[47:32];
    else if(read_fifo_wadrs&(~RSTATE))
        reg_mem_rdata <= fifo_wadrs;
    else if(read_fifo_warea&(~RSTATE))
        reg_mem_rdata <= fifo_warea;
    else if(read_fifo_ctl&(~RSTATE))
        reg_mem_rdata <= {15'h0000,fifo_run, 7'h00,
                            fifo_reg_eflag, 8'h00};
        
// ---------------------------------
// 各種リセット同期化
// ---------------------------------
always@(posedge cpuclk or posedge RST)
    if(RST) begin
        RST_cpuclk_sync1 <= 1'b1;
        RST_cpuclk_sync2 <= 1'b1;
    end
    else begin
        RST_cpuclk_sync1 <= RST;
        RST_cpuclk_sync2 <= RST_cpuclk_sync1;
    end
assign WSHRST = RST_cpuclk_sync2;

always@(posedge psramclk or posedge RST)
    if(RST) begin
        RST_psramclk_sync1 <= 1'b1;
        RST_psramclk_sync2 <= 1'b1;
    end
    else begin
        RST_psramclk_sync1 <= RST;
        RST_psramclk_sync2 <= RST_psramclk_sync1;
    end
assign PSRST = RST_psramclk_sync2;

// ---------------------------------
// freerun timer
// ---------------------------------
always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        free_timer <= 48'h0000_00000000;
    else
        free_timer <= free_timer + 48'h0000_00000001;

// --------------------------------------------------
// Logic Analyzer 用 観測用トリガ生成 デバッグ信号
// ---------------------------------
// reg_w_ready モニタ
// ---------------------------------
/*
reg [15:0] reg_w_ready_cnt;
reg reg_w_ready2;
wire reg_w_ready2_r;
wire reg_w_ready2_f;
reg reg_w_ready_cnten;

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        reg_w_ready2 <= 1'b1;
    else
        reg_w_ready2 <= reg_w_ready;

assign reg_w_ready2_f = (~reg_w_ready) & reg_w_ready2;
assign reg_w_ready2_r = reg_w_ready & (~reg_w_ready2);
wire    trg_reg_w_ready_cnt;
assign trg_reg_w_ready_cnt = (reg_w_ready_cnt == 16'd256);

always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        reg_w_ready_cnten <= 1'b0;
    else if(reg_w_ready2_f)
        reg_w_ready_cnten <= 1'b1;
    else if(reg_w_ready2_r)
        reg_w_ready_cnten <= 1'b0;


always@(posedge cpuclk or posedge WSHRST)
    if(WSHRST)
        reg_w_ready_cnt <= 16'h0000;
    else if(reg_w_ready_cnten)
        reg_w_ready_cnt <= reg_w_ready_cnt + 16'h0001;
    else
        reg_w_ready_cnt <= 16'h0000;
*/


brd_wb2ps_wc_fifodma brd_wb2ps_wc_fifodma
(
    // System Signals
    .WSHRST(WSHRST),
    .cpuclk(cpuclk),       // wishbone clk

    // System Signals PSRAM
    .PSRST(PSRST),
    .psclk(psclk),       // psram clk

    .fifo_wdata_wen2(fifo_wdata_wen2),      // in
    .fifo_wdata(fifo_wdata),                // in
    .fifo_wadrs(fifo_wadrs),                // in
    .fifo_warea(fifo_warea),                // in
    .fifo_startp(fifo_startp),              // in
    .fifo_endp(fifo_endp),
    .fifo_almost_full(fifo_almost_full),    // output
    .fifo_run(fifo_run),                    // output
    .fifo_run_endp(fifo_run_endp),          // output

    // PSRAM IF
    .psram_cmd(cmd_fifo),
    .psram_cmd_en(cmd_en_fifo),
    .psram_addr(addr_fifo),
    .psram_wdata(wr_data_fifo),
    .psram_mask(data_mask_fifo),
    .psram_ready(cmd_ready_fifo)

);

endmodule