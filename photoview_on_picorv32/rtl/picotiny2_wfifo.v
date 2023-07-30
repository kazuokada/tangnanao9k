`timescale 1ns/1ps

module picotiny (
  input clk,
  input resetn,

  output       tmds_clk_n,
  output       tmds_clk_p,
  output [2:0] tmds_d_n,
  output [2:0] tmds_d_p,

  output  flash_clk,
  output  flash_csb,
  inout   flash_mosi,
  inout   flash_miso,

  input  ser_rx,
  output ser_tx,
  //inout [6:0] gpio,
  
  output    o_SPI_Clk,
  input     i_SPI_MISO,
  output    o_SPI_MOSI,
  output    o_SPI_CS_n,
  
    output [1:0] O_psram_ck,       // Magic ports for PSRAM to be inferred
    output [1:0] O_psram_ck_n,
    inout [1:0] IO_psram_rwds,
    inout [15:0] IO_psram_dq,
    output [1:0] O_psram_reset_n,
    output [1:0] O_psram_cs_n,
    
    //LED
    // LED[5:0]=pin16,15,14,13,11,10
    // 0: run_hdmi
    // 1: vsync_flg
    // 2: 1sec blink
    output wire [2:0] LED

);

reg [23:0]  sec_counter;
reg         bring_1sec;

 wire sys_resetn;

 wire mem_valid;
 wire mem_ready;
 wire [31:0] mem_addr;
 wire [31:0] mem_wdata;
 wire [3:0] mem_wstrb;
 wire [31:0] mem_rdata;

 wire spimemxip_valid;
 wire spimemxip_ready;
 wire [31:0] spimemxip_addr;
 wire [31:0] spimemxip_wdata;
 wire [3:0] spimemxip_wstrb;
 wire [31:0] spimemxip_rdata;

 wire sram_valid;
 wire sram_ready;
 wire [31:0] sram_addr;
 wire [31:0] sram_wdata;
 wire [3:0] sram_wstrb;
 wire [31:0] sram_rdata;

 wire picop_valid;
 wire picop_ready;
 wire [31:0] picop_addr;
 wire [31:0] picop_wdata;
 wire [3:0] picop_wstrb;
 wire [31:0] picop_rdata;

 wire wbp_valid;
 wire wbp_ready;
 wire [31:0] wbp_addr;
 wire [31:0] wbp_wdata;
 wire [3:0] wbp_wstrb;
 wire [31:0] wbp_rdata;
 
 wire spimemcfg_valid;
 wire spimemcfg_ready;
 wire [31:0] spimemcfg_addr;
 wire [31:0] spimemcfg_wdata;
 wire [3:0] spimemcfg_wstrb;
 wire [31:0] spimemcfg_rdata;

 wire brom_valid;
 wire brom_ready;
 wire [31:0] brom_addr;
 wire [31:0] brom_wdata;
 wire [3:0] brom_wstrb;
 wire [31:0] brom_rdata;

 wire gpio_valid;
 wire gpio_ready;
 wire [31:0] gpio_addr;
 wire [31:0] gpio_wdata;
 wire [3:0] gpio_wstrb;
 wire [31:0] gpio_rdata;

 wire uart_valid;
 wire uart_ready;
 wire [31:0] uart_addr;
 wire [31:0] uart_wdata;
 wire [3:0] uart_wstrb;
 wire [31:0] uart_rdata;

 wire spi_sd_valid;
 wire spi_sd_ready;
 wire [31:0] spi_sd_addr;
 wire [31:0] spi_sd_wdata;
 wire [3:0] spi_sd_wstrb;
 wire [31:0] spi_sd_rdata;


wire            hdmireg_valid;
wire            hdmireg_ready;
wire [31:0]     hdmireg_addr;
wire [31:0]     hdmireg_wdata;
wire [3:0]      hdmireg_wstrb;
wire [31:0]     hdmireg_rdata;
 
wire            hdmi_psram_cmd;
wire            hdmi_psram_cmd_en;
wire [22:0]     hdmi_psram_addr;
wire [31:0]     hdmi_psram_rdata;
wire            hdmi_psram_rvalid;
wire            hdmi_psram_cmd_ready;

wire            psram_cmd;
wire            psram_cmd_en;
wire [22:0]     psram_addr;
wire [31:0]     psram_rdata;
wire            psram_rvalid;
wire [31:0]     psram_wdata;
wire [3:0]      psram_mask;
wire            psram_cmd_ready;

wire            cache_reg_valid;
wire            cache_reg_ready;
wire [31:0]     cache_reg_addr;
wire [31:0]     cache_reg_wdata;
wire [3:0]      cache_reg_wstrb;
wire [31:0]     cache_reg_rdata;

// fifo側のPSRAM I/F wonly
wire            cmd_fifo;
wire            cmd_en_fifo;
wire [22:0]     addr_fifo;
wire [31:0]     wr_data_fifo;
wire [3:0]      data_mask_fifo;
wire            cmd_ready_fifo;


 
wire clk_p;
wire clk_p5;
wire pll_lock;

// clk = 27MHz
// localparam PLL_IDIV  =  3 - 1; // 0~63
// localparam PLL_FBDIV = 14- 1; // 0~63 nano-9k 1080p
// localparam PLL_ODIV  =      4; // 2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128
// clkout = (27x14)/3 = 126MHz
// f_CLKOUT = f_CLKIN * FBDIV / IDIV, 3.125~600MHz
// f_VCO = f_CLKOUT * ODIV, 400~1200MHz
//       = 126*4 = 504MHz
// f_PFD = f_CLKIN / IDIV = f_CLKOUT / FBDIV, 3~400MHz
//       = 27 / 3 = 126/14 = 9

wire    clkout_371p25m;
wire    clkout_74p25m;
wire    clkout_37p125m;
assign  clk_p = clkout_37p125m;
    Gowin_rPLL_HDMI u_Gowin_rPLL_HDMI(
        .clkout(clkout_371p25m), //output clkout 371.25MHz
        .lock(pll_lock), //output lock
        .clkin(clk) //input clkin  27MHz
    );

    Gowin_CLKDIV5 u_Gowin_CLKDIV5(
        .clkout(clkout_74p25m), //output clkout
        .hclkin(clkout_371p25m), //input hclkin
        .resetn(pll_lock) //input resetn
    );
    Gowin_CLKDIV2_37 u_Gowin_CLKDIV2(
        .clkout(clkout_37p125m), //output clkout
        .hclkin(clkout_74p25m), //input hclkin
        //.hclkin(clkout_371p25m), //input hclkin
        .resetn(pll_lock) //input resetn
    );


Reset_Sync u_Reset_Sync (
  .resetn(sys_resetn),
  .ext_reset(resetn & pll_lock),
  .clk(clk_p)
);

picorv32 #(
   .PROGADDR_RESET(32'h8000_0000)
) u_picorv32 (
   .clk(clk_p),
   .resetn(sys_resetn),
   .trap(),
   .mem_valid(mem_valid),
   .mem_instr(),
   .mem_ready(mem_ready),
   .mem_addr(mem_addr),     // out
   .mem_wdata(mem_wdata),   // out
   .mem_wstrb(mem_wstrb),   // out
   .mem_rdata(mem_rdata),   // in
   .irq(32'b0),
   .eoi()
 );

 PicoMem_SRAM_8KB u_PicoMem_SRAM_8KB_7 (
  .resetn(sys_resetn),
  .clk(clk_p),
  .mem_s_valid(sram_valid),
  .mem_s_ready(sram_ready),
  .mem_s_addr(sram_addr),
  .mem_s_wdata(sram_wdata),
  .mem_s_wstrb(sram_wstrb),
  .mem_s_rdata(sram_rdata)
 );
 
 // S0 0x0000_0000 -> SPI Flash XIP
 // S1 0x4000_0000 -> SRAM
 // S2 0x8000_0000 -> PicoPeriph
 // S3  -> Wishbone
 PicoMem_Mux_1_4 u_PicoMem_Mux_1_4_8 (
// slave i/f
  .picom_valid(mem_valid),    // in
  .picom_ready(mem_ready),    // out
  .picom_addr(mem_addr),      // in  32bit
  .picom_wdata(mem_wdata),    // in
  .picom_wstrb(mem_wstrb),    // in
  .picom_rdata(mem_rdata),    // out 32bit

// master i/f				      
  .picos0_valid(spimemxip_valid),    // out
  .picos0_ready(spimemxip_ready),    // in
  .picos0_addr(spimemxip_addr),      // out
  .picos0_wdata(spimemxip_wdata),    // out
  .picos0_wstrb(spimemxip_wstrb),    // out
  .picos0_rdata(spimemxip_rdata),    // in

  .picos1_valid(sram_valid),
  .picos1_ready(sram_ready),
  .picos1_addr(sram_addr),
  .picos1_wdata(sram_wdata),
  .picos1_wstrb(sram_wstrb),
  .picos1_rdata(sram_rdata),

    // Peripheral
  .picos2_valid(picop_valid),
  .picos2_ready(picop_ready),
  .picos2_addr(picop_addr),
  .picos2_wdata(picop_wdata),
  .picos2_wstrb(picop_wstrb),
  .picos2_rdata(picop_rdata),

    // PSRAM area
  .picos3_valid(wbp_valid),
  .picos3_ready(wbp_ready),
  .picos3_addr(wbp_addr),
  .picos3_wdata(wbp_wdata),
  .picos3_wstrb(wbp_wstrb),
  .picos3_rdata(wbp_rdata)
 );

// S0 0x8000_0000 -> BOOTROM
// S1 0x8100_0000 -> SPI Flash
// S2 0x8200_0000 -> GPIO
// S3 0x8300_0000 -> UART
// S4 0x8400_0000 -> SPI SDcard
// S5 0x8500_0000 -> HDMI reg
// S6 0x8600_0000 -> CACHE reg
  PicoMem_Mux_1_7 #(
    .PICOS0_ADDR_BASE(32'h8000_0000),
    .PICOS0_ADDR_MASK(32'h0F00_0000),
    .PICOS1_ADDR_BASE(32'h8100_0000),
    .PICOS1_ADDR_MASK(32'h0F00_0000),
    .PICOS2_ADDR_BASE(32'h8200_0000),
    .PICOS2_ADDR_MASK(32'h0F00_0000),
    .PICOS3_ADDR_BASE(32'h8300_0000),
    .PICOS3_ADDR_MASK(32'h0F00_0000),
    .PICOS4_ADDR_BASE(32'h8400_0000),
    .PICOS4_ADDR_MASK(32'h0F00_0000),
    .PICOS5_ADDR_BASE(32'h8500_0000),
    .PICOS5_ADDR_MASK(32'h0F00_0000),
    .PICOS6_ADDR_BASE(32'h8600_0000),
    .PICOS6_ADDR_MASK(32'h0F00_0000)
  ) u_PicoMem_Mux_1_7_picop (
  .picom_valid(picop_valid),
  .picom_ready(picop_ready),
  .picom_addr(picop_addr),
  .picom_wdata(picop_wdata),
  .picom_wstrb(picop_wstrb),
  .picom_rdata(picop_rdata),

  .picos0_valid(brom_valid),
  .picos0_ready(brom_ready),
  .picos0_addr(brom_addr),
  .picos0_wdata(brom_wdata),
  .picos0_wstrb(brom_wstrb),
  .picos0_rdata(brom_rdata),

  .picos1_valid(spimemcfg_valid),
  .picos1_ready(spimemcfg_ready),
  .picos1_addr(spimemcfg_addr),
  .picos1_wdata(spimemcfg_wdata),
  .picos1_wstrb(spimemcfg_wstrb),
  .picos1_rdata(spimemcfg_rdata),

  .picos2_valid(gpio_valid),
  .picos2_ready(gpio_ready),
  .picos2_addr(gpio_addr),
  .picos2_wdata(gpio_wdata),
  .picos2_wstrb(gpio_wstrb),
  .picos2_rdata(gpio_rdata),

  .picos3_valid(uart_valid),
  .picos3_ready(uart_ready),
  .picos3_addr(uart_addr),
  .picos3_wdata(uart_wdata),
  .picos3_wstrb(uart_wstrb),
  .picos3_rdata(uart_rdata),

  .picos4_valid(spi_sd_valid),
  .picos4_ready(spi_sd_ready),
  .picos4_addr(spi_sd_addr),
  .picos4_wdata(spi_sd_wdata),
  .picos4_wstrb(spi_sd_wstrb),
  .picos4_rdata(spi_sd_rdata),

  .picos5_valid(hdmireg_valid),
  .picos5_ready(hdmireg_ready),
  .picos5_addr(hdmireg_addr),
  .picos5_wdata(hdmireg_wdata),
  .picos5_wstrb(hdmireg_wstrb),
  .picos5_rdata(hdmireg_rdata), 

  .picos6_valid(cache_reg_valid),
  .picos6_ready(cache_reg_ready),
  .picos6_addr(cache_reg_addr),
  .picos6_wdata(cache_reg_wdata),
  .picos6_wstrb(cache_reg_wstrb),
  .picos6_rdata(cache_reg_rdata)
 );

 PicoMem_SPI_Flash u_PicoMem_SPI_Flash_18 (
  .clk    (clk_p),
  .resetn (sys_resetn),

  .flash_csb  (flash_csb),
  .flash_clk  (flash_clk),
  .flash_mosi (flash_mosi),
  .flash_miso (flash_miso),

  .flash_mem_valid  (spimemxip_valid),
  .flash_mem_ready  (spimemxip_ready),
  .flash_mem_addr   (spimemxip_addr),
  .flash_mem_wdata  (spimemxip_wdata),
  .flash_mem_wstrb  (spimemxip_wstrb),
  .flash_mem_rdata  (spimemxip_rdata),

  .flash_cfg_valid  (spimemcfg_valid),
  .flash_cfg_ready  (spimemcfg_ready),
  .flash_cfg_addr   (spimemcfg_addr),
  .flash_cfg_wdata  (spimemcfg_wdata),
  .flash_cfg_wstrb  (spimemcfg_wstrb),
  .flash_cfg_rdata  (spimemcfg_rdata)
 );

 PicoMem_BOOT_SRAM_8KB u_boot_sram (
  .resetn(sys_resetn),
  .clk(clk_p),
  .mem_s_valid(brom_valid),
  .mem_s_ready(brom_ready),
  .mem_s_addr(brom_addr),
  .mem_s_wdata(brom_wdata),
  .mem_s_wstrb(brom_wstrb),
  .mem_s_rdata(brom_rdata)
 );

//assign gpio[0] = run_hdmi;
//assign gpio[1] = vsync_flg;
assign gpio_ready = 1'b1;
assign gpio_rdata = 32'h0000_0000;
/*
 PicoMem_GPIO u_PicoMem_GPIO (
  .resetn(sys_resetn),
  .io({gpio[6:2],2'bzz}),
  .clk(clk_p),
  .busin_valid(gpio_valid),
  .busin_ready(gpio_ready),
  .busin_addr(gpio_addr),
  .busin_wdata(gpio_wdata),
  .busin_wstrb(gpio_wstrb),
  .busin_rdata(gpio_rdata)
 );
*/
 PicoMem_UART u_PicoMem_UART (
  .resetn(sys_resetn),
  .clk(clk_p),
  .mem_s_valid(uart_valid),
  .mem_s_ready(uart_ready),
  .mem_s_addr(uart_addr),
  .mem_s_wdata(uart_wdata),
  .mem_s_wstrb(uart_wstrb),
  .mem_s_rdata(uart_rdata),
  .ser_rx(ser_rx),
  .ser_tx(ser_tx)
 );


assign wbp_ready = 1'b1;
/*
wire svo_term_valid;
assign svo_term_valid = (uart_valid && uart_ready) & (~uart_addr[2]) & uart_wstrb[0];

svo_hdmi_top u_hdmi (
	.clk(clk_p),
	.resetn(sys_resetn),

	// video clocks
	.clk_pixel(clk_p),
	.clk_5x_pixel(clk_p5),
	.locked(pll_lock),

	.term_in_tvalid( svo_term_valid ),
	.term_out_tready(),
	.term_in_tdata( uart_wdata[7:0] ),

	// output signals
	.tmds_clk_n(tmds_clk_n),
	.tmds_clk_p(tmds_clk_p),
	.tmds_d_n(tmds_d_n),
	.tmds_d_p(tmds_d_p)
);
*/

spi_top  #(
  .SPI_MODE( 0),
  .CLKS_PER_HALF_BIT(2),
  .MAX_BYTES_PER_CS( 2),
  .CS_INACTIVE_CLKS(1)
  ) u_spi_top
(
    .rstn(sys_resetn),
    .clk(clk_p),     // 126MHz/5 clk
    
    // wish bone
    .spi_mem_addr(spi_sd_addr[11:0]),
    .spi_mem_wdata(spi_sd_wdata),
    .spi_mem_rdata(spi_sd_rdata),
    .spi_mem_wstrb(spi_sd_wstrb),
    .spi_mem_valid(spi_sd_valid),
    .spi_mem_ready(spi_sd_ready),
    
    // SPI master i/f
    .o_SPI_Clk(o_SPI_Clk),
//    .i_SPI_MISO(i_SPI_MISO),
    .i_SPI_MISO(i_SPI_MISO),
    .o_SPI_MOSI(o_SPI_MOSI),
    .o_SPI_CS_n(o_SPI_CS_n)
    );

// HDMI I/F
wire        out_rgb_de;
wire        out_rgb_vs;
wire        out_rgb_hs;
wire [7:0]  out_r;
wire [7:0]  out_g;
wire [7:0]  out_b;
wire        run_hdmi;
wire        vsync_flg;
wire [31:0] DUMMY_REG;

// LEDは正負逆 0で点灯
assign LED[0] = ~run_hdmi;
assign LED[1] = ~vsync_flg;


psram_hdmi_top 
    #(.HDMI_HSIZE(1280),
      .HDMI_VSIZE(720)
      ) u_psram_hdmi_top
(
    .rst_n(sys_resetn),           // psramclk同期化済み  // in
    .psramclk(half_psramclk),    //82.5MHz  // in
    .hdmiclk(clkout_74p25m),      //74.25MHz // in
    .reg_clk(clk_p),          // in
    
    // PSRAM コマンドインターフェース
    .psram_cmd(hdmi_psram_cmd),             // out
    .psram_cmd_en(hdmi_psram_cmd_en),       // out
    .psram_addr(hdmi_psram_addr[22:2]),     // out
    .psram_rdata(hdmi_psram_rdata),         // in
    .psram_rvalid(hdmi_psram_rvalid),       // in
    .psram_cmd_ready(hdmi_psram_cmd_ready), // in
    
    // wishbone i/f (for reg)
    .reg_mem_addr(hdmireg_addr[11:0]),    // in
    .reg_mem_wdata(hdmireg_wdata),  // in
    .reg_mem_rdata(hdmireg_rdata),  // out
    .reg_mem_wstrb(hdmireg_wstrb),  // in
    .reg_mem_valid(hdmireg_valid),  // in
    .reg_mem_ready(hdmireg_ready),  // out

    // HDMI
    .out_rgb_de(out_rgb_de),
    .out_rgb_vs(out_rgb_vs),
    .out_rgb_hs(out_rgb_hs),
    .out_r(out_r),
    .out_g(out_g),
    .out_b(out_b),

    // LED
    .run_hdmi(run_hdmi),    // out
    .vsync_flg(vsync_flg),  // out
    // dummy reg
    .DUMMY_REG(DUMMY_REG)   // out
);

// S3 0xC000_0000 -> PSRAM
wire init_calib0;
wire init_calib1;
wire clk_out;
wire [31:0] rd_data0;
wire [31:0] rd_data1;
wire rd_data_valid0;
wire rd_data_valid1;
//wire [1:0] IO_psram_rwds;
//wire [15:0] IO_psram_dq;
wire half_psramclk;

wire psramclk_lock_o;
/*
     Gowin_rPLL_psram upll_psram_memclk(
        .clkout(psramclk), //output clkout: 165.375MHz
        .clkin(clk), //input clkin   // 27MHz
        .lock_o(psramclk_lock_o)
    );
*/
    Gowin_rPLL_psram upll_psram_memclk(
        .clkout(psramclk), //output clkout  165.375MHz
        .lock(psramclk_lock_o), //output lock
        .clkin(clk) //input clkin  27MHz
    );
    
brd_wb2ps_wfifo u_brd_wb2ps_wfifo (
    .RST(~sys_resetn),
    .cpuclk(clk_p),       // wishbone clk

    // reg i/f
    .reg_mem_addr(cache_reg_addr[11:0]),  // input wire [11:0]
    .reg_mem_wdata(cache_reg_wdata),      // input wire [31:0]
    .reg_mem_rdata(cache_reg_rdata),      // output reg [31:0]
    .reg_mem_wstrb(cache_reg_wstrb),      // input wire [3:0] 
    .reg_mem_valid(cache_reg_valid),      // input wire       
    .reg_mem_ready(cache_reg_ready),      // output wire      

    // PSRAM i/f
    // psramclk domain
    .half_psramclk(half_psramclk),       // 83MHz clk

    // fifo側のPSRAM I/F
    .cmd_fifo(cmd_fifo),            //output cmd0
    .cmd_en_fifo(cmd_en_fifo),      //output cmd_en0
    .addr_fifo(addr_fifo),
    .wr_data_fifo(wr_data_fifo),
    .data_mask_fifo(data_mask_fifo),
    .cmd_ready_fifo(cmd_ready_fifo)    // in
    );
// -------------------------
// バススイッチ
// ch0優先で設計しているのでch0にHDMIポートを繋ぐこと
// -------------------------
psram_arb
    #(.TCMD_cyc(26)
     ) u_psram_arb
(
    .rst_n(sys_resetn),     // in psramclk同期化済み
    .psramclk(half_psramclk),  // in 82.5MHz
    
    // PSRAM コマンドインターフェース(アービトレーション後)
    .psram_cmd(psram_cmd),          // out
    .psram_cmd_en(psram_cmd_en),    // out
    .psram_addr(psram_addr[22:0]),  // out [22:0]
    .psram_rdata(psram_rdata),      // in
    .psram_rvalid(psram_rvalid),    // in
    .psram_wdata(psram_wdata),      // out
    .psram_mask(psram_mask),        // out
    
    // アービトレーション前 I/F
    .cmd_s0(hdmi_psram_cmd),            // in
    .cmd_en_s0(hdmi_psram_cmd_en),      // in
    .addr_s0({hdmi_psram_addr[22:2],2'b00}),  // in
    .rdata_s0(hdmi_psram_rdata),        // out
    .rvalid_s0(hdmi_psram_rvalid),      // out
    .wdata_s0(32'h0),                   // in
    .mask_s0(4'h0),                     // in
    .cmd_ready_s0(hdmi_psram_cmd_ready),   // out

    // cache
    .cmd_s1(1'b0),          // in
    .cmd_en_s1(1'b0),       // in
    .addr_s1(23'b0),        // in
    .rdata_s1(),            // out
    .rvalid_s1(),           // out
    .wdata_s1(32'b0),       // in
    .mask_s1(4'b0),         // in
    .cmd_ready_s1(),        // out

    // fifo
    .cmd_s2(cmd_fifo),      // in
    .cmd_en_s2(cmd_en_fifo),// in
    .addr_s2(addr_fifo),    // in
    .rdata_s2(),            // out
    .rvalid_s2(),           // out
    .wdata_s2(wr_data_fifo),    // in
    .mask_s2(data_mask_fifo),   // in
    .cmd_ready_s2(cmd_ready_fifo)   // out

);    
// ch1は使わない
// データ共有が出来ない為
	PSRAM_Memory_Interface_HS_2CH_Top u_PSRAM(
		.clk(clk), //input clk 27MHz
		.rst_n(sys_resetn), //input rst_n
		.memory_clk(psramclk), //input memory_clk
		.pll_lock(psramclk_lock_o), //input pll_lock
		.O_psram_ck(O_psram_ck), //output [1:0] O_psram_ck
		.O_psram_ck_n(O_psram_ck_n), //output [1:0] O_psram_ck_n
		.IO_psram_rwds(IO_psram_rwds), //inout [1:0] IO_psram_rwds
		.O_psram_reset_n(O_psram_reset_n), //output [1:0] O_psram_reset_n
		.IO_psram_dq(IO_psram_dq), //inout [15:0] IO_psram_dq
		.O_psram_cs_n(O_psram_cs_n), //output [1:0] O_psram_cs_n
		.init_calib0(init_calib0_o), //output init_calib0
		.init_calib1(init_calib1_o), //output init_calib1
		.clk_out(half_psramclk), //output clk_out
		.cmd0(psram_cmd), //input cmd0
		.cmd1(1'b0),
		.cmd_en0(psram_cmd_en), //input cmd_en0
        .cmd_en1(1'b0),
		// ↓2byteアドレス
		.addr0(psram_addr[21:1]), //input [20:0] addr0
		.addr1(21'h00000),
		.wr_data0(psram_wdata), //input [31:0] wr_data0
		.wr_data1(32'h0000_0000), //input [31:0] wr_data1
		.rd_data0(psram_rdata), //output [31:0] rd_data0
		.rd_data1(),
		.rd_data_valid0(psram_rvalid), //output rd_data_valid0
        .rd_data_valid1(),
		.data_mask0(psram_mask), //input [3:0] data_mask0
		.data_mask1(4'h0)
	);

	DVI_TX_Top u_DVI_TX_Top(
		.I_rst_n(sys_resetn), //input I_rst_n
		.I_serial_clk(clkout_371p25m), //input I_serial_clk
		.I_rgb_clk(clkout_74p25m), //input I_rgb_clk
		.I_rgb_vs(out_rgb_vs), //input I_rgb_vs
		.I_rgb_hs(out_rgb_hs), //input I_rgb_hs
		.I_rgb_de(out_rgb_de), //input I_rgb_de
		.I_rgb_r(out_r), //input [7:0] I_rgb_r
		.I_rgb_g(out_g), //input [7:0] I_rgb_g
		.I_rgb_b(out_b), //input [7:0] I_rgb_b
		.O_tmds_clk_p(tmds_clk_p), //output O_tmds_clk_p
		.O_tmds_clk_n(tmds_clk_n), //output O_tmds_clk_n
		.O_tmds_data_p(tmds_d_p), //output [2:0] O_tmds_data_p
		.O_tmds_data_n(tmds_d_n) //output [2:0] O_tmds_data_n
	);
	
always@(posedge clk or negedge sys_resetn)
    if(~sys_resetn)
        sec_counter <= 24'd0;
    else if(sec_counter==24'd1349_9999)
        sec_counter <= 24'd0;
    else
        sec_counter <= sec_counter + 1'b1;

always@(posedge clk or negedge sys_resetn)
    if(~sys_resetn)
        bring_1sec <= 1'b0;
    else if(sec_counter==24'd1349_9999)
        bring_1sec <= ~bring_1sec;

assign LED[2]=bring_1sec;

endmodule
