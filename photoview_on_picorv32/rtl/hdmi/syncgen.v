`timescale 1ns / 1ps
// HDMI表示用のタイミングジェネレータ

module syncgen (
    input  wire         rst_n,
    input  wire         clk_pixel,  //74.25MHz for 720p
    input  wire         run_timinggen,
    output reg          rgb_vs,
    output reg          rgb_hs,
    output reg          rgb_de,
    output reg          frame_last_pix

);

// f_CLKOUT = f_CLKIN * FBDIV / IDIV, 3.125~600MHz
// f_VCO = f_CLKOUT * ODIV, 400~1200MHz
// f_PFD = f_CLKIN / IDIV = f_CLKOUT / FBDIV, 3~400MHz

/*
// XGA
localparam PLL_IDIV  =  10 - 1; // 0~63
//localparam PLL_FBDIV = 57 - 1; // 0~63  nano-4k
localparam PLL_FBDIV = 52 - 1; // 0~63 nano-9k 1080p
localparam PLL_ODIV  =      2; // 2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128
//localparam PLL_ODIV  =      4; // 2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128
*/

/*
// 1920x1080
localparam PLL_IDIV  =  2 - 1; // 0~63
localparam PLL_FBDIV = 44 - 1; // 0~63 nano-9k 1080p
localparam PLL_ODIV  =      2; // 2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128
*/
// 720p(1280x720@60p)
// f_CLKOUT = (27x33) / 6 = 148.5MHz = serial clock
localparam PLL_IDIV  =  6 - 1; // 0~63
localparam PLL_FBDIV = 33 - 1; // 0~63 nano-9k 1080p
localparam PLL_ODIV  =      4; // 2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128


// 720p(1280x720@60p)
// pix clk:74.25MHz
localparam DVI_H_BPORCH = 12'd220;
localparam DVI_H_ACTIVE = 12'd1280;
localparam DVI_H_FPORCH = 12'd110;
localparam DVI_H_SYNC   = 12'd40;
localparam DVI_H_POLAR  = 1'b1;
localparam DVI_V_BPORCH = 12'd20;
localparam DVI_V_ACTIVE = 12'd720;
localparam DVI_V_FPORCH = 12'd5;
localparam DVI_V_SYNC   = 12'd5;
localparam DVI_V_POLAR  = 1'b1;

// XGA 1024x768
// pixel clock : 65.0MHz
/*
localparam DVI_H_BPORCH = 12'd160;
localparam DVI_H_ACTIVE = 12'd1024;
localparam DVI_H_FPORCH = 12'd24;
localparam DVI_H_SYNC   = 12'd136;
localparam DVI_H_POLAR  = 1'b0;
localparam DVI_V_BPORCH = 12'd29;
localparam DVI_V_ACTIVE = 12'd768;
localparam DVI_V_FPORCH = 12'd3;
localparam DVI_V_SYNC   = 12'd6;
localparam DVI_V_POLAR  = 1'b0;
*/

/*
// 1080p
// pixel clock : 148.5MHz -> DVI_TXがmax:80MHzなので対応できない
localparam DVI_H_BPORCH = 12'd148;
localparam DVI_H_ACTIVE = 12'd1920;
localparam DVI_H_FPORCH = 12'd88;
localparam DVI_H_SYNC   = 12'd44;
localparam DVI_H_POLAR  = 1'b1;
localparam DVI_V_BPORCH = 12'd36;
localparam DVI_V_ACTIVE = 12'd1080;
localparam DVI_V_FPORCH = 12'd4;
localparam DVI_V_SYNC   = 12'd5;
localparam DVI_V_POLAR  = 1'b1;
*/

// 1440p
/*
localparam DVI_H_BPORCH = 12'd40;
localparam DVI_H_ACTIVE = 12'd2560;
localparam DVI_H_FPORCH = 12'd8;
localparam DVI_H_SYNC   = 12'd32;
localparam DVI_H_POLAR  = 1'b1;
localparam DVI_V_BPORCH = 12'd6;
localparam DVI_V_ACTIVE = 12'd1440;
localparam DVI_V_FPORCH = 12'd13;
localparam DVI_V_SYNC   = 12'd8;
localparam DVI_V_POLAR  = 1'b0;
*/
//localparam DVI_H_BPORCH = 12'd80;
//localparam DVI_H_ACTIVE = 12'd2560;
//localparam DVI_H_FPORCH = 12'd48;
//localparam DVI_H_SYNC   = 12'd32;
//localparam DVI_H_POLAR  = 1'b1;
//localparam DVI_V_BPORCH = 12'd33;
//localparam DVI_V_ACTIVE = 12'd1440;
//localparam DVI_V_FPORCH = 12'd3;
//localparam DVI_V_SYNC   = 12'd5;
//localparam DVI_V_POLAR  = 1'b0;


// Video Timing Generator

reg [11:0] cnt_h;
reg [11:0] cnt_h_next;
reg [11:0] cnt_v;
reg [11:0] cnt_v_next;

always @(negedge rst_n or posedge clk_pixel)
    if (!rst_n) begin
        cnt_h <= 12'd0;
        cnt_v <= 12'd0;
    end else if (!run_timinggen) begin
        cnt_h <= 12'd0;
        cnt_v <= 12'd0;
    end else begin
        cnt_h <= cnt_h_next;
        cnt_v <= cnt_v_next;
    end

always @(*) begin
    if (cnt_h == DVI_H_BPORCH + DVI_H_ACTIVE + DVI_H_FPORCH + DVI_H_SYNC - 1'd1) begin
        cnt_h_next = 12'd0;
        if (cnt_v == DVI_V_BPORCH + DVI_V_ACTIVE + DVI_V_FPORCH + DVI_V_SYNC - 1'd1) begin
            cnt_v_next = 12'd0;
        end else begin
            cnt_v_next = cnt_v + 1'd1;
        end
    end else begin
        cnt_h_next = cnt_h + 1'd1;
        cnt_v_next = cnt_v;
    end
end

//                |--> cnt start
// ____|__|~~~~~~~|____|____________________|__|~~~~~~~|___
//      FP  H_SYNC  BP   H_ACTIVE            FP
always @(posedge clk_pixel)
    if (!run_timinggen)
        rgb_hs <= ~DVI_H_POLAR;
    else if (cnt_h < DVI_H_BPORCH + DVI_H_ACTIVE + DVI_H_FPORCH)
        rgb_hs <= ~DVI_H_POLAR;
    else
        rgb_hs <= DVI_H_POLAR;

always @(posedge clk_pixel)
    if (!run_timinggen)
        rgb_vs <= ~DVI_V_POLAR;
    else if (cnt_v < DVI_V_BPORCH + DVI_V_ACTIVE + DVI_V_FPORCH)
        rgb_vs <= ~DVI_V_POLAR;
    else
        rgb_vs <= DVI_V_POLAR;

always @(posedge clk_pixel)
    if (!run_timinggen)
        rgb_de <= 1'b0;
    else if (cnt_h < DVI_H_BPORCH || cnt_h >= DVI_H_BPORCH + DVI_H_ACTIVE)
        rgb_de <= 1'b0;
    else if (cnt_v < DVI_V_BPORCH || cnt_v >= DVI_V_BPORCH + DVI_V_ACTIVE)
        rgb_de <= 1'b0;
    else
        rgb_de <= 1'b1;
        
always @(posedge clk_pixel)
    frame_last_pix <=   (cnt_h == (DVI_H_BPORCH + DVI_H_ACTIVE) ) &
                        (cnt_v == (DVI_V_BPORCH + DVI_V_ACTIVE) );
        
endmodule
