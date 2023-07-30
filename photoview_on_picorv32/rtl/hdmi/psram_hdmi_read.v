`timescale 1ns / 1ps
// HDMI表示用のfifo書き込み
// 1280x720
// fifo 64byte x 4段
module psram_hdmi_read 
#(
    parameter TCMD_cyc = 26,
    parameter HDMI_HSIZE = 1280,
    parameter HDMI_VSIZE = 720
    )
(
    input  wire         rst_n_psclk, // psramclk同期化済み
    input  wire         psramclk,  //82.5MHz
    
    // PSRAM コマンドインターフェース
    output wire         psram_cmd,
    output reg          psram_cmd_en,
    output reg [22:2]   psram_addr,
    input wire [31:0]   psram_rdata,
    input wire          psram_rvalid,
    input wire          psram_cmd_ready,
    // reg i/f
    input wire          start_hdmi,
    input wire          stop_hdmi,
    input wire [22:0]   start_adrs, // read先頭アドレス(画像の先頭)
    output reg          run_hdmi,
    
    // disp_hdmi i/f
    output reg          fifo_empty,
    
    // fifo i/f
    output wire [7:2]   fifo_adr,
    output wire         fifo_wen,
    output wire [31:0]  fifo_wdata,
    input  wire         fifo_rpt_update_hdclk
);

// ---------------------------------
// 内部信号
// ---------------------------------

wire        rst_psclk = ~rst_n_psclk;

reg         start_hdmi_psclk_sync1;
reg         start_hdmi_psclk_sync2;
wire        start_hdmi_psclk_rise;
reg         stop_hdmi_psclk_sync1;
reg         stop_hdmi_psclk_sync2;
wire        stop_hdmi_psclk_rise;

reg [3:0]   STATE;
reg [3:0]   next_STATE;

reg [4:0]   tcmd_cnt;
reg [3:0]   rvalid_cnt;

reg [22:2]  start_adrs_r;

reg [10:0]  hcnt;
reg [10:0]  vcnt;

reg [2:0]   fifo_wpt;   // 4段分 4x64byte
reg [2:0]   fifo_rpt;   // 4段分 4x64byte

reg         fifo_rpt_update_sync1;
reg         fifo_rpt_update_sync2;
reg         fifo_rpt_update_sync3;
wire        rise_fifo_rpt_update;

wire [2:0]  fifo_delta;
wire        fifo_wready;
reg [2:0]   fifo_adr_org;

// ----------------------------
// start_hdmi同期化
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk) begin
        start_hdmi_psclk_sync1 <= 1'b0;
        start_hdmi_psclk_sync2 <= 1'b0;
    end
    else begin
        start_hdmi_psclk_sync1 <= start_hdmi;
        start_hdmi_psclk_sync2 <= start_hdmi_psclk_sync1;
    end

assign start_hdmi_psclk_rise =
            start_hdmi_psclk_sync1 & (~start_hdmi_psclk_sync2);


// ----------------------------
// stop_hdmi同期化
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk) begin
        stop_hdmi_psclk_sync1 <= 1'b0;
        stop_hdmi_psclk_sync2 <= 1'b0;
    end
    else begin
        stop_hdmi_psclk_sync1 <= stop_hdmi;
        stop_hdmi_psclk_sync2 <= stop_hdmi_psclk_sync1;
    end
assign stop_hdmi_psclk_rise =
            stop_hdmi_psclk_sync1 & (~stop_hdmi_psclk_sync2);

// ---------------------------------
// STATE machine
// ---------------------------------
parameter   S0  = 4'h0,
            S1  = 4'h1,
            S2  = 4'h2,
            S3  = 4'h3,
            S4  = 4'h4,
            S5  = 4'h5,
            S6  = 4'h6,
            S7  = 4'h7,
            S8  = 4'h8,
            S9  = 4'h9,
            SA  = 4'ha,
            SB  = 4'hb,
            SC  = 4'hc,
            SD  = 4'hd,
            SE  = 4'he,
            SF  = 4'hf;
            
wire        S0ack=(STATE==S0);
wire        S1ack=(STATE==S1);
wire        S2ack=(STATE==S2);
wire        S3ack=(STATE==S3);
wire        S4ack=(STATE==S4);
wire        S5ack=(STATE==S5);
wire        S6ack=(STATE==S6);
wire        S7ack=(STATE==S7);
wire        S8ack=(STATE==S8);
wire        S9ack=(STATE==S9);

always@(posedge psramclk or posedge rst_psclk)
    if (rst_psclk)
        STATE <= S0;
    else
        STATE <= next_STATE;

always@* begin
    case (STATE)
        S0 : if(start_hdmi_psclk_sync2)
                next_STATE = S1;
             else
                next_STATE = S0;
        S1 : next_STATE = S5;
        S2 : if(psram_rvalid&(rvalid_cnt == 4'd15))
                next_STATE = S3;
             else
                next_STATE = S2;
        S3 : if( (tcmd_cnt == (TCMD_cyc-2)) |
                    (tcmd_cnt == (TCMD_cyc-1)) ) begin
                if(stop_hdmi_psclk_sync2)
                    next_STATE = S0;
                else if(~fifo_wready)
                    next_STATE = S4;
                else
                    next_STATE = S1;
             end
             else
                next_STATE = S3;
        S4 : if(~fifo_wready)
                next_STATE = S4;
              else
                next_STATE = S1;
        S5 : if(psram_cmd_ready)
                next_STATE = S3;
             else
                next_STATE = S5;
             
        default : next_STATE = S0;
    endcase
end

// ----------------------------
// rvalid_cnt
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        rvalid_cnt <= 4'h0;
    //else if(S0ack|S1ack)
    else if(S0ack)
        rvalid_cnt <= 4'h0;
    //else if(S2ack&psram_rvalid)
    else if(psram_rvalid)
        rvalid_cnt <= rvalid_cnt + 4'h1;

// ----------------------------
// tcmd_cnt
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        tcmd_cnt <= 5'h00;
    else if(S2ack|S3ack|(S5ack&psram_cmd_ready)) begin
        if(tcmd_cnt!=(TCMD_cyc-1))
            tcmd_cnt <= tcmd_cnt + 5'h01;
    end
    else
        tcmd_cnt <= 5'h00;
    
// ----------------------------
// PSRAM I/F
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        psram_cmd_en <= 1'b0;
    else if(psram_cmd_ready)
        psram_cmd_en <= 1'b0;
    else if(S1ack)
        psram_cmd_en <= 1'b1;

assign  psram_cmd = 1'b0;   // read

// ----------------------------
// reg 取り込み 非同期 安定タイミング
// ----------------------------
always@(posedge psramclk)
    if(S1ack) begin
        if ((hcnt == 11'h000) & (vcnt == 11'h000))  //開始時
            psram_addr <= start_adrs[22:2];
        else
            psram_addr <= psram_addr + 21'd16;
    end

// ----------------------------
// hcnt, vcnt
// ----------------------------
always@(posedge psramclk)
    if(S0ack)
        hcnt <= 11'h000;
    //else if(S2ack&psram_rvalid&(rvalid_cnt == 4'd15)) begin
    //else if(psram_rvalid&(rvalid_cnt == 4'd15)) begin
    else if(S5ack & psram_cmd_ready) begin
        if(hcnt == (HDMI_HSIZE-32))
            hcnt <= 11'd0;
        else
            hcnt <= hcnt + 11'd32;      // +32pix(16bot/pix)
    end
    
always@(posedge psramclk)
    if(S0ack)
        vcnt <= 11'h000;
    //else if(S2ack&psram_rvalid&(rvalid_cnt == 4'd15)) begin
    //else if(psram_rvalid&(rvalid_cnt == 4'd15)) begin
    else if(S5ack & psram_cmd_ready) begin
    //else if(S1ack) begin
        if(hcnt == (HDMI_HSIZE-32)) begin
            if( vcnt == (HDMI_VSIZE-1))
                vcnt <= 11'd0;
            else
                vcnt <= vcnt + 11'd1;      // +1line
        end
    end

    
// ----------------------------
// 動作ステータス
// ----------------------------
always@(posedge psramclk)
    run_hdmi <= ~S0ack;
    
// ----------------------------
// fifo_wpt
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        fifo_wpt <= 3'h0;
    else if(S0ack)
        fifo_wpt <= 3'h0;
    //else if((psram_rvalid&(rvalid_cnt == 4'd15)))
    else if(S5ack & psram_cmd_ready)
        fifo_wpt <= fifo_wpt + 3'h1;

// ----------------------------
// fifo_rpt
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk) begin
        fifo_rpt_update_sync1 <= 1'b0;
        fifo_rpt_update_sync2 <= 1'b0;
        fifo_rpt_update_sync3 <= 1'b0;
    end
    else begin
        fifo_rpt_update_sync1 <= fifo_rpt_update_hdclk;
        fifo_rpt_update_sync2 <= fifo_rpt_update_sync1;
        fifo_rpt_update_sync3 <= fifo_rpt_update_sync2;
    end
assign rise_fifo_rpt_update =
    fifo_rpt_update_sync2 & (~fifo_rpt_update_sync3);

always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        fifo_rpt <= 3'h0;
    else if(S0ack)
        fifo_rpt <= 3'h0;
    else if(rise_fifo_rpt_update)
        fifo_rpt <= fifo_rpt + 3'h1;

// ----------------------------
// fifo_empty/wready
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        fifo_empty <= 1'b0;
    else if(fifo_rpt==fifo_wpt)
        fifo_empty <= 1'b1;
    else
        fifo_empty <= 1'b0;

assign fifo_delta =  fifo_wpt - fifo_rpt;

// wpt-rpt=0,1,2,3 OK
//        =4,5,6,7 NG
assign fifo_wready = ~fifo_delta[2];

// ----------------------------
// fifo ram control
// ----------------------------
always@(posedge psramclk or posedge rst_psclk)
    if(rst_psclk)
        fifo_adr_org <= 3'h0;
    else if(S0ack)
        fifo_adr_org <= 3'h0;
    else if((psram_rvalid&(rvalid_cnt == 4'd15)))
        fifo_adr_org <= fifo_adr_org + 3'h1;
        
assign fifo_adr = {fifo_adr_org[1:0],rvalid_cnt};  // 6bit = 2bit + 4bit
assign fifo_wen = psram_rvalid;
assign fifo_wdata = psram_rdata;



endmodule
