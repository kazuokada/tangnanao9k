`timescale 1ns/1ps
// SPI_Master.v
// に対し
// wish bone if 化
// tx_fifo, rx_fifo 8段
// spi clock  生成用分周器
// spi 動作モード
//

module spi_top 
  #(parameter SPI_MODE = 0,
    parameter CLKS_PER_HALF_BIT = 2,
    parameter MAX_BYTES_PER_CS = 2,
    parameter CS_INACTIVE_CLKS = 1)
(
    input wire          rstn,
    input wire          clk,     // 126MHz clk
    
    // wish bone
    input wire [11:0]   spi_mem_addr,
    input wire [31:0]   spi_mem_wdata,
    output reg [31:0]   spi_mem_rdata,
    input wire [3:0]    spi_mem_wstrb,
    input wire          spi_mem_valid,
    output wire         spi_mem_ready,
    
    // SPI master i/f
    output wire          o_SPI_Clk,
    input  wire          i_SPI_MISO,
    output wire          o_SPI_MOSI,
    output reg           o_SPI_CS_n

    );


reg  [7:0]  i_TX_Byte;
reg         i_TX_DV;
wire        o_TX_Ready;
wire        o_RX_DV;
wire [7:0]  o_RX_Byte;

reg [7:0]   txdata_fifo[0:7];
reg [7:0]   rxdata_fifo[0:7];
reg         mem_w_ready;
wire        mem_r_ready;
reg         RSTATE;

reg [3:0]   txdata_wpt;
reg [3:0]   txdata_rpt;
reg [3:0]   rxdata_wpt;
reg [3:0]   rxdata_rpt;
wire        txdata_wen;
wire        txfifo_almostfull;
wire        txdata_ready;
wire        txfifo_empty;

// status系
reg         SPI_BSY;
reg         SPI_TFE;    // txfifo empty
reg         SPI_TFF;    // txfifo almost full
reg         SPI_RNE;    // rxfifo not empty
reg         SPI_RF;     // rxfifo full

// debug系
reg [31:0]  DEBUG;
reg [31:0]  DEBUG2;
wire [31:0] DEBUG_rise;

assign spi_mem_ready = mem_r_ready & mem_w_ready ;

  // Instantiate Master
  SPI_Master 
    #(.SPI_MODE(SPI_MODE),
      .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT)
      ) SPI_Master_Inst
   (
   // Control/Data Signals,
   .i_Rst_L(rstn),     // FPGA Reset
   .i_Clk(clk),         // FPGA Clock
   
   // TX (MOSI) Signals
   .i_TX_Byte(i_TX_Byte),         // Byte to transmit
   .i_TX_DV(i_TX_DV),             // Data Valid Pulse 
   .o_TX_Ready(o_TX_Ready),   // Transmit Ready for Byte
   
   // RX (MISO) Signals
   .o_RX_DV(o_RX_DV),       // Data Valid pulse (1 clock cycle)
   .o_RX_Byte(o_RX_Byte),   // Byte received on MISO

   // SPI Interface
   .o_SPI_Clk(o_SPI_Clk),
   .i_SPI_MISO(i_SPI_MISO),
   .o_SPI_MOSI(o_SPI_MOSI)
   );

// ------------------------------------
// txfifo wpt
// ------------------------------------
assign txdata_wen = (spi_mem_addr==12'h008)&
                    spi_mem_valid&(|spi_mem_wstrb)&mem_w_ready;

always@(negedge rstn or posedge clk)
    if(~rstn)
        txdata_wpt <= 4'h0;
    else if(txdata_wen)
        txdata_wpt <= txdata_wpt + 4'h1;
// ------------------------------------
// txdata_rpt
// ------------------------------------
always@(negedge rstn or posedge clk)
    if(~rstn)
        txdata_rpt <= 4'h0;
    else if(i_TX_DV)
        txdata_rpt <= txdata_rpt + 4'h1;

// -------------------------------------
// txfifo_almostfull
// txfifoがフルになる一つ手前でアサート
//  fullでもアサートされる
// -------------------------------------
assign txfifo_almostfull = ((txdata_wpt-txdata_rpt)==4'h7) |
                            ((txdata_wpt-txdata_rpt)==4'h8) ;

// -------------------------------------
// txdata_ready
// txfifoあり
// -------------------------------------
assign txdata_ready = (|(txdata_wpt-txdata_rpt));

// -------------------------------------
// txfifo_empty
// -------------------------------------
assign txfifo_empty = (txdata_wpt == txdata_rpt);

// -------------------------------------
// mem_w_ready
// write アクセス
// ready信号
// -------------------------------------
always@(negedge rstn or posedge clk)
    if(~rstn)
        mem_w_ready <= 1'b1;
    else
        //mem_w_ready <= ~txfifo_almostfull;
        mem_w_ready <= 1'b1;


// -------------------------------------
// txdata_fifo
// -------------------------------------
always@(posedge clk)
    if(txdata_wen)
        txdata_fifo[txdata_wpt[2:0]] <= spi_mem_wdata[7:0];
        
// -------------------------------------
// i_TX_Byte (送信データ)
// i_TX_DV (送信enable 1shot)
// -------------------------------------
always@(posedge clk)
    if(o_TX_Ready&txdata_ready)
        i_TX_Byte <= txdata_fifo[txdata_rpt[2:0]];

always@(negedge rstn or posedge clk)
    if(~rstn)
        i_TX_DV <= 1'b0;
    else if(i_TX_DV)
        i_TX_DV <= 1'b0;
    else if(o_TX_Ready&txdata_ready)
        i_TX_DV <= 1'b1;

// -------------------------------------
// SPI_BSY 
// -------------------------------------
always@(negedge rstn or posedge clk)
    if(~rstn)
        SPI_BSY <= 1'b0;
    else if(o_RX_DV & txfifo_empty)
        SPI_BSY <= 1'b0;
    else if(i_TX_DV & txdata_ready)
        SPI_BSY <= 1'b1;
// -------------------------------------
// SPI_TFE 
// txfifo empty
// -------------------------------------
always@(negedge rstn or posedge clk)
    if(~rstn)
        SPI_TFE <= 1'b1;
    else
        SPI_TFE <= txfifo_empty;
        
always@(negedge rstn or posedge clk)
    if(~rstn)
        SPI_TFF <= 1'b0;
    else
        SPI_TFF <= txfifo_almostfull;

// -------------------------------------
// SPI_RNE 
// rxfifo not empty
// -------------------------------------
always@(negedge rstn or posedge clk)
    if(~rstn)
        SPI_RNE <= 1'b0;
    else if(o_RX_DV)
        SPI_RNE <= 1'b1;
    else if(rxdata_wpt==rxdata_rpt)
        SPI_RNE <= 1'b0;

always@(negedge rstn or posedge clk)
    if(~rstn)
        SPI_RF <= 1'b0;
    else 
        SPI_RF <= (rxdata_wpt[3]^rxdata_rpt[3])&
                    (rxdata_wpt[2:0]==rxdata_rpt[2:0]);
                    
// ------------------------------------
// rxdata_wpt, rpt
// rptはレジスタリードでupdate
// ------------------------------------
always@(negedge rstn or posedge clk)
    if(~rstn)
        rxdata_wpt <= 4'h0;
    else if(o_RX_DV)
        rxdata_wpt <= rxdata_wpt + 4'h1;

// read busタイミング
wire read_bus;
wire read_rxdata_bus;
wire read_status_bus;
assign read_bus = spi_mem_valid & (spi_mem_wstrb==4'h0);
assign read_rxdata_bus = (spi_mem_addr==12'h00c)&
                         spi_mem_valid & (spi_mem_wstrb==4'h0);

assign read_status_bus = (spi_mem_addr==12'h010)&
                         spi_mem_valid & (spi_mem_wstrb==4'h0);
               
always@(negedge rstn or posedge clk)
    if(~rstn)
        rxdata_rpt <= 4'h0;
    else if( read_rxdata_bus & (~RSTATE) )
        rxdata_rpt <= rxdata_rpt + 4'h1;

// ------------------------------------
// mem_r_ready (read側 wishbone ready)
// ------------------------------------
assign mem_r_ready = ~(read_bus & (~RSTATE));

// ------------------------------------
// RSTATE (read bus timing 後半サイクル)
// ------------------------------------
always@(negedge rstn or posedge clk)
    if(~rstn)
        RSTATE <= 1'b0;
    else if(RSTATE)
        RSTATE <= 1'b0;
    else if(read_bus)
        RSTATE <= 1'b1;

// -------------------------------------
// rxdata_fifo
// -------------------------------------
always@(posedge clk)
    if(o_RX_DV)
        rxdata_fifo[rxdata_wpt[2:0]] <= o_RX_Byte;

// -------------------------------------
// bus
// spi_mem_rdata
// -------------------------------------
always@(posedge clk)
    if(read_rxdata_bus&(~RSTATE))
        spi_mem_rdata <= {24'h000000,rxdata_fifo[rxdata_rpt[2:0]]};
    else if(read_status_bus&(~RSTATE))
        spi_mem_rdata <= {24'h000000,3'h0,SPI_RF,SPI_RNE,SPI_TFF,SPI_TFE,SPI_BSY};
        
// -------------------------------------
// o_SPI_CS_n
// CS出力
// -------------------------------------
wire write_CSREG_bus;
assign write_CSREG_bus = (spi_mem_addr==12'h014)&
                         spi_mem_valid & (spi_mem_wstrb[0]==1'b1);

always@(negedge rstn or posedge clk)
    if(~rstn)
        o_SPI_CS_n <= 1'b1;
    else if(write_CSREG_bus)
        o_SPI_CS_n <= spi_mem_wdata[0];

// -------------------------------------
// DEBUG用 ロジアナトリガ
// -------------------------------------
wire write_DEBUG_bus;
assign write_DEBUG_bus = (spi_mem_addr==12'h020)&
                         spi_mem_valid & (|spi_mem_wstrb);

always@(negedge rstn or posedge clk)
    if(~rstn)
        DEBUG <= 32'h0000;
    else if(write_DEBUG_bus)
        DEBUG <= spi_mem_wdata;

always@(negedge rstn or posedge clk)
    if(~rstn)
        DEBUG2 <= 32'h0000;
    else
        DEBUG2 <= DEBUG;

assign DEBUG_rise = DEBUG&(~DEBUG2);

endmodule