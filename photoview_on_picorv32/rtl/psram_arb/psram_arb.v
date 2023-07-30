`timescale 1ns / 1ps
// PSRAM I/F arbiter
// 3ch版
// 優先順位
// S0: 最強
// S1,S2 : 交互
module psram_arb 
#(
    parameter TCMD_cyc = 27
    )
(
    input  wire         rst_n, // psramclk同期化済み
    input  wire         psramclk,  //82.5MHz
    
    // PSRAM コマンドインターフェース(アービトレーション後)
    output reg          psram_cmd,
    output reg          psram_cmd_en,
    output reg [22:0]   psram_addr,
    input wire [31:0]   psram_rdata,
    input wire          psram_rvalid,
    output reg [31:0]   psram_wdata,
    output reg [3:0]    psram_mask,
    
    // アービトレーション前 I/F
    input wire          cmd_s0,
    input wire          cmd_en_s0,
    input wire [22:0]   addr_s0,
    output wire [31:0]  rdata_s0,
    output wire         rvalid_s0,
    input wire [31:0]   wdata_s0,
    input wire [3:0]    mask_s0,
    output reg          cmd_ready_s0,
    

    input wire          cmd_s1,
    input wire          cmd_en_s1,
    input wire [22:0]   addr_s1,
    output wire [31:0]  rdata_s1,
    output wire         rvalid_s1,
    input wire [31:0]   wdata_s1,
    input wire [3:0]    mask_s1,
    output reg          cmd_ready_s1,

    input wire          cmd_s2,
    input wire          cmd_en_s2,
    input wire [22:0]   addr_s2,
    output wire [31:0]  rdata_s2,
    output wire         rvalid_s2,
    input wire [31:0]   wdata_s2,
    input wire [3:0]    mask_s2,
    output reg          cmd_ready_s2

);

// ---------------------------------
// 内部信号
// ---------------------------------

wire        rst_psclk;

reg [1:0]   next_service0;
reg [1:0]   next_service1;
reg [1:0]   cur_service;

reg [1:0]   sel_ch;
reg         cmd_en_hold;
reg [4:0]   tcmd_cnt;
reg [1:0]   sel_rvalid;
reg [3:0]   rvalid_cnt;
reg [31:0]  rdata_sx;
reg         rvalid_sx;

reg         rst_n_psclk_sync1;
reg         rst_n_psclk_sync2;

reg         sel_s1s2;   // 0:s1, 1:s2

// 
// reset 同期化
// 
always@(posedge psramclk or negedge rst_n)
    if(!rst_n) begin
        rst_n_psclk_sync1 <= 1'b0;
        rst_n_psclk_sync2 <= 1'b0;
    end
    else begin
        rst_n_psclk_sync1 <= rst_n;
        rst_n_psclk_sync2 <= rst_n_psclk_sync1;
    end
assign rst_psclk = ~rst_n_psclk_sync2;

// ----------------------------
// next_service0
// 次回にサービスを受けるべきch
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        next_service0 <= 2'b00;
    // S0 S1 S2
    //  1  x  x  -> 01 or 10
    else if(cmd_en_s0&cmd_ready_s0)
        next_service0 <= 1'b1;
    else if(cmd_en_s1&cmd_ready_s1)
        next_service0 <= 1'b0;

// ----------------------------
// next_service1
// cmd_ready_sxでラッチ
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        next_service1 <= 1'b0;
    else if(cmd_ready_s0|cmd_ready_s1|cmd_ready_s2)
        next_service1 <= next_service0;

// ----------------------------
// cur_service
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        cur_service <= 2'b00;
    else if(cmd_en_s0&cmd_ready_s0)
        cur_service <= 2'b00;
    else if(cmd_en_s1&cmd_ready_s1)
        cur_service <= 2'b01;
    else if(cmd_en_s2&cmd_ready_s2)
        cur_service <= 2'b10;
    
// ----------------------------
// sel_rvalid
// rvalid 選択ch
// ----------------------------
always@(posedge psramclk)
    if(psram_rvalid&(rvalid_cnt==4'h0))
        sel_rvalid <= cur_service;
        
// ----------------------------
// プライオリティ
// = cmd_ready*
// s0優先
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        cmd_ready_s0 <= 1'b0;
    else if(cmd_ready_s0)
        cmd_ready_s0 <= 1'b0;
    else if( (tcmd_cnt==5'h00) & (~cmd_ready_s1) & (~cmd_ready_s2) ) begin
        //if( cmd_en_s0 & cmd_en_s1 ) begin
        //        cmd_ready_s0 <= 1'b1;
        //end
        //else if(cmd_en_s0)
        //    cmd_ready_s0 <= 1'b1;
        if(cmd_en_s0)
            cmd_ready_s0 <= 1'b1;
    end

always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        cmd_ready_s1 <= 1'b0;
    else if(cmd_ready_s1)
        cmd_ready_s1 <= 1'b0;
    else if( (tcmd_cnt==5'h00) & (~cmd_ready_s0) & (~cmd_ready_s2) ) begin
        if(cmd_en_s1 & (~cmd_en_s0)) begin
            if(cmd_en_s2 & (~sel_s1s2)) // s2が来ていてもsel_s1s2=0なので
                cmd_ready_s1 <= 1'b1;
            else if(cmd_en_s2 & sel_s1s2)
                cmd_ready_s1 <= 1'b0;
            else    // s2が来ていなければ
                cmd_ready_s1 <= 1'b1;
        end
    end

always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        cmd_ready_s2 <= 1'b0;
    else if(cmd_ready_s2)
        cmd_ready_s2 <= 1'b0;
    else if( (tcmd_cnt==5'h00) & (~cmd_ready_s0) & (~cmd_ready_s1) ) begin
        if(cmd_en_s2 & (~cmd_en_s0)) begin
            if(cmd_en_s1 & sel_s1s2) // s1が来ていてもsel_s1s2=1なのでs2選択
                cmd_ready_s2 <= 1'b1;
            else if(cmd_en_s1 & (~sel_s1s2)) // S1が来ていてsel_s1s2=0(s1優先)ならready_s2=0
                cmd_ready_s2 <= 1'b0;
            else    // s1が来ていなければ
                cmd_ready_s2 <= 1'b1;
        end
    end

always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        sel_s1s2 <= 1'b0;
    else if(cmd_ready_s1)
        sel_s1s2 <= 1'b1;   // S2優先
    else if(cmd_ready_s2)
        sel_s1s2 <= 1'b0;   // S1優先
// ----------------------------
// 各信号選択
// ----------------------------
always@(posedge psramclk)
    if(cmd_ready_s0) begin
        psram_cmd <= cmd_s0;
        psram_addr <= addr_s0;
    end
    else if(cmd_ready_s1) begin
        psram_cmd <= cmd_s1;
        psram_addr <= addr_s1;
    end
    else if(cmd_ready_s2) begin
        psram_cmd <= cmd_s2;
        psram_addr <= addr_s2;
    end

always@(posedge psramclk)
    if(cmd_ready_s0 | ((cur_service==2'b00)&(~cmd_ready_s1)&(~cmd_ready_s2)) ) begin
        psram_wdata <= wdata_s0;
        psram_mask <= mask_s0;
    end
    else if(cmd_ready_s1 | ((cur_service==2'b01)&(~cmd_ready_s0)&(~cmd_ready_s2)) ) begin
        psram_wdata <= wdata_s1;
        psram_mask <= mask_s1;
    end
    else if(cmd_ready_s2 | ((cur_service==2'b10)&(~cmd_ready_s0)&(~cmd_ready_s1)) ) begin
        psram_wdata <= wdata_s2;
        psram_mask <= mask_s2;
    end
    
always@(posedge psramclk)
    // 1shot
    psram_cmd_en <= (cmd_ready_s0 | cmd_ready_s1 | cmd_ready_s2);

// ----------------------------
// cmd間隔
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        cmd_en_hold <= 1'b0;
    else if(psram_cmd_en)
        cmd_en_hold <= 1'b1;
    else if(tcmd_cnt == (TCMD_cyc-2) )
        cmd_en_hold <= 1'b0;
/*    
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        tcmd_cnt <= (TCMD_cyc-1);
    else if(cmd_ready_s0 | cmd_ready_s1)
        tcmd_cnt <= 5'h00;
    else if( psram_cmd_en | cmd_en_hold ) begin
        if( tcmd_cnt == (TCMD_cyc-1) )
            tcmd_cnt <= 5'h00;
        else
        //if( tcmd_cnt != (TCMD_cyc-1) )
            tcmd_cnt <= tcmd_cnt + 5'h01;
    end
*/
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        tcmd_cnt <= 5'h00;
    else if(cmd_ready_s0 | cmd_ready_s1 |cmd_ready_s2)
        tcmd_cnt <= 5'h01;
    else if( psram_cmd_en | cmd_en_hold ) begin
        if( tcmd_cnt == (TCMD_cyc-2) )
            tcmd_cnt <= 5'h00;
        else
            tcmd_cnt <= tcmd_cnt + 5'h01;
    end
    
// ----------------------------
// rvalid_cnt
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        rvalid_cnt <= 4'h0;
    else if(psram_rvalid)
        rvalid_cnt <= rvalid_cnt + 4'h1;
    
// ----------------------------
// rvalid_s*
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        rvalid_sx <= 1'b0;
    else
        rvalid_sx <= psram_rvalid;

assign rvalid_s0 = (sel_rvalid==2'b00)&rvalid_sx;
assign rvalid_s1 = (sel_rvalid==2'b01)&rvalid_sx;
assign rvalid_s2 = (sel_rvalid==2'b10)&rvalid_sx;

always@(posedge psramclk)
    if(psram_rvalid)
        rdata_sx <= psram_rdata;

assign rdata_s0 = rdata_sx;
assign rdata_s1 = rdata_sx;
assign rdata_s2 = rdata_sx;



endmodule
