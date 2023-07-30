`timescale 1ns/1ps

module fifo_1rd1wr
  #(
    //---------------------------------------------------------------
    parameter   ADDR_WIDTH              =  8, // Addr  Width in bits : 2**ADDR_WIDTH = RAM Depth
    parameter   DATA_WIDTH              =  32  // Data  Width in bits
    //---------------------------------------------------------------
    ) (
        // write port
        input clkA,
        input enaA, 
        input weA,
        input [ADDR_WIDTH-1:0] addrA,
        input [DATA_WIDTH-1:0] dinA,
        //output reg [DATA_WIDTH-1:0] doutA,
       
        // read port
        input clkB,
        input enaB,
        input [ADDR_WIDTH-1:0] addrB,
        //input [DATA_WIDTH-1:0] dinB,
        output reg [DATA_WIDTH-1:0] doutB
        );

    reg [DATA_WIDTH-1:0]    ram_block [(2**ADDR_WIDTH)-1:0];

    always @(posedge clkA) 
        if (enaA&weA) begin
            ram_block[addrA] <= dinA;
        end
 
            
    always@(posedge clkB)
        if(enaB)
            doutB <= ram_block[addrB]; 

endmodule 


