`timescale 1ns / 1ps
// HDMI表示用のfifo書き込み
// 1280x720
// fifo 64byte x 4段
module psram_hdmi_disp (
    input  wire         rst_n_hdclk,    // hdmiclk同期化済み
    input  wire         hdmiclk,        //74.25MHz
    
    
    // reg i/f
    input wire          start_hdmi,
    input wire          stop_hdmi,
    output reg          disp_run,
    output reg          fifo_underrun,
    input wire          clr_fifo_underrun,
    output reg          VSYNC_flag,
    input wire          clr_VSYNC_flag,
    
    // disp_hdmi i/f
    input wire          fifo_empty, // psramclk
    
    // fifo i/f
    output reg [7:2]    fifo_radr,
    output reg          fifo_ren,
    input wire [31:0]   fifo_rdata,
    output reg          fifo_rpt_update_hdclk,
    
    // from timing generator
    input wire          in_rgb_de,
    input wire          in_rgb_vs,
    input wire          in_rgb_hs,
    input wire          in_frame_last_pix,
    
    output reg          run_timinggen,
    output wire         out_rgb_de,
    output wire         out_rgb_vs,
    output wire         out_rgb_hs,
    output reg [7:0]    out_r,
    output reg [7:0]    out_g,
    output reg [7:0]    out_b
);

// ---------------------------------
// 内部信号
// ---------------------------------

wire        rst_hdclk = ~rst_n_hdclk;

reg         start_hdmi_hdclk_sync1;
reg         start_hdmi_hdclk_sync2;
wire        start_hdmi_hdclk_rise;

reg         fifo_empty_sync1;
reg         fifo_empty_sync2;
reg         fifo_empty_sync3;
wire        fall_fifo_empty;

reg         stop_hdmi_hdclk_sync1;
reg         stop_hdmi_hdclk_sync2;
wire        stop_hdmi_hdclk_rise;

reg [2:0]   pre_rgb_de;
reg [2:0]   pre_rgb_vs;
reg [2:0]   pre_rgb_hs;
reg         fifo_rdat_sel;

reg         clr_fifo_underrun_sync1;
reg         clr_fifo_underrun_sync2;
reg         clr_fifo_underrun_sync3;
reg         VSYNC_flag;
reg         clr_VSYNC_flag_sync1;
reg         clr_VSYNC_flag_sync2;
reg         clr_VSYNC_flag_sync3;


// ----------------------------
// start_hdmi同期化
// ----------------------------
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk) begin
        start_hdmi_hdclk_sync1 <= 1'b0;
        start_hdmi_hdclk_sync2 <= 1'b0;
    end
    else begin
        start_hdmi_hdclk_sync1 <= start_hdmi;
        start_hdmi_hdclk_sync2 <= start_hdmi_hdclk_sync1;
    end

assign start_hdmi_hdclk_rise =
            start_hdmi_hdclk_sync1 & (~start_hdmi_hdclk_sync2);

// ----------------------------
// stop_hdmi同期化
// ----------------------------
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk) begin
        stop_hdmi_hdclk_sync1 <= 1'b0;
        stop_hdmi_hdclk_sync2 <= 1'b0;
    end
    else begin
        stop_hdmi_hdclk_sync1 <= stop_hdmi;
        stop_hdmi_hdclk_sync2 <= stop_hdmi_hdclk_sync1;
    end
assign stop_hdmi_hdclk_rise =
            stop_hdmi_hdclk_sync1 & (~stop_hdmi_hdclk_sync2);

// ----------------------------
// fifo_empty同期化
// ----------------------------
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk) begin
        fifo_empty_sync1 <= 1'b1;
        fifo_empty_sync2 <= 1'b1;
        fifo_empty_sync3 <= 1'b1;
    end
    else begin
        fifo_empty_sync1 <= fifo_empty;
        fifo_empty_sync2 <= fifo_empty_sync1;
        fifo_empty_sync3 <= fifo_empty_sync2;
    end
assign fall_fifo_empty = ~fifo_empty_sync2 & fifo_empty_sync3;

// ----------------------------
// disp_run
// ----------------------------
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk)
        disp_run <= 1'b0;
    else if(start_hdmi_hdclk_sync2&(~fifo_empty_sync2))
        disp_run <= 1'b1;
    else if(stop_hdmi_hdclk_sync2 & in_frame_last_pix)
        disp_run <= 1'b0;
        

// ----------------------------
// run_timinggen
// ----------------------------
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk)
        run_timinggen <= 1'b0;
    else if(start_hdmi_hdclk_sync2&(~fifo_empty_sync2))
        run_timinggen <= 1'b1;
    else if(stop_hdmi_hdclk_sync2 & in_frame_last_pix)
        run_timinggen <= 1'b0;

// ----------------------------
// fifo_rctl
// ----------------------------
// fifoは32bitで2pixずつ格納されている為
// 2回に一回読みだす事とする
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk)
        fifo_ren <= 1'b0;
    else if(~run_timinggen)
        fifo_ren <= 1'b0;
    else if( in_rgb_de )
        fifo_ren <= ~fifo_ren;

always@(posedge hdmiclk)
    if(~run_timinggen)
        fifo_radr <= 6'h00;
    else if(fifo_ren)
        fifo_radr <= fifo_radr + 6'h01;
// ----------------------------
// fifo_rpt_update_hdclk
// rpt更新通知
// hdmiclk x 4 pulse
// psramclk側はこれを同期化出来る必要があるので
// hdmiclk周期 x 4 > psramclk周期
// の関係を満たす事
// hdmiclk=13ns, psramclk=12ns
// ----------------------------
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk)
        fifo_rpt_update_hdclk <= 1'b0;
    else if(~disp_run)
        fifo_rpt_update_hdclk <= 1'b0;
    else if( (fifo_radr[5:2]==4'h0) & fifo_ren)
        fifo_rpt_update_hdclk <= 1'b0;
    else if( (fifo_radr[5:2]==4'hf) & fifo_ren)
        fifo_rpt_update_hdclk <= 1'b1;
// ----------------------------
// DVI I/F
// ----------------------------
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk) begin
        pre_rgb_de <= 3'b000;
        pre_rgb_vs <= 3'b000;
        pre_rgb_hs <= 3'b000;
    end
    else if(~run_timinggen) begin
        pre_rgb_de <= 3'b000;
        pre_rgb_vs <= 3'b000;
        pre_rgb_hs <= 3'b000;
    end
    else begin
        pre_rgb_de <= {pre_rgb_de[1:0], in_rgb_de};
        pre_rgb_vs <= {pre_rgb_vs[1:0], in_rgb_vs};
        pre_rgb_hs <= {pre_rgb_hs[1:0], in_rgb_hs};
    end
assign out_rgb_de = pre_rgb_de[2];
assign out_rgb_vs = pre_rgb_vs[2];
assign out_rgb_hs = pre_rgb_hs[2];

// RGB565をRGB888へ
always@(posedge hdmiclk)
    fifo_rdat_sel <= fifo_ren;
        
always@(posedge hdmiclk)
    if(fifo_rdat_sel) begin
        out_r <= {fifo_rdata[15:11],{3{fifo_rdata[11]}} };
        out_g <= {fifo_rdata[10:5],{2{fifo_rdata[5]}} };
        out_b <= {fifo_rdata[4:0],{3{fifo_rdata[0]}} };
    end
    else begin
        out_r <= {fifo_rdata[15+16:11+16],{3{fifo_rdata[11+16]}} };
        out_g <= {fifo_rdata[10+16:5+16],{2{fifo_rdata[5+16]}} };
        out_b <= {fifo_rdata[4+16:0+16],{3{fifo_rdata[0+16]}} };
    end
    
// ----------------------------
// fifo_underrun
// ----------------------------
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk)
        fifo_underrun <= 1'b0;
    else if(clr_fifo_underrun_sync2 & (~clr_fifo_underrun_sync3))
        fifo_underrun <= 1'b0;
    else if(disp_run) begin
        if(fall_fifo_empty)
            fifo_underrun <= 1'b1;
    end


always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk) begin
        clr_fifo_underrun_sync1 <= 1'b0;
        clr_fifo_underrun_sync2 <= 1'b0;
        clr_fifo_underrun_sync3 <= 1'b0;
    end
    else begin
        clr_fifo_underrun_sync1 <= clr_fifo_underrun;
        clr_fifo_underrun_sync2 <= clr_fifo_underrun_sync1;
        clr_fifo_underrun_sync3 <= clr_fifo_underrun_sync2;
    end

// ----------------------------
// VSYNC_flag
// ----------------------------
always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk)
        VSYNC_flag <= 1'b0;
    else if(clr_VSYNC_flag_sync2 & (~clr_VSYNC_flag_sync3))
        VSYNC_flag <= 1'b0;
    else if(~pre_rgb_vs[0] & (pre_rgb_vs[1]))
        VSYNC_flag <= 1'b1;

always@(posedge hdmiclk or posedge rst_hdclk)
    if(rst_hdclk) begin
        clr_VSYNC_flag_sync1 <= 1'b0;
        clr_VSYNC_flag_sync2 <= 1'b0;
        clr_VSYNC_flag_sync3 <= 1'b0;
    end
    else begin
        clr_VSYNC_flag_sync1 <= clr_VSYNC_flag;
        clr_VSYNC_flag_sync2 <= clr_VSYNC_flag_sync1;
        clr_VSYNC_flag_sync3 <= clr_VSYNC_flag_sync2;
    end
     
endmodule
