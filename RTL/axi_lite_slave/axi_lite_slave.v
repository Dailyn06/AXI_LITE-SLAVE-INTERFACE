`timescale 1ns/1ps
module axi_lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_REGS   =4

)(
    input wire clk,
    input wire reset,

    //Write Address Channel
    input wire [ADDR_WIDTH-1 : 0] s_awaddr,
    input wire                    s_awvalid,
    output wire                    s_awready,

    //Write Data Channel
    input wire [DATA_WIDTH-1:0]   s_wdata,
    input wire                    s_wvalid,
    input wire [3:0]              s_wstrb, //write store bit
    output wire                    s_wready,

    //write Response Channel
    input wire        s_bready,
    output reg [1:0]  s_bresp,
    output reg        s_bvalid,

    // Read Address Channel
    input wire [ADDR_WIDTH-1:0]   s_araddr,
    input wire                    s_arvalid,
    output wire                    s_arready,

    // Read Data Channel
    input wire                    s_rready,
    output reg [DATA_WIDTH-1:0]   s_rdata,
    output reg [1:0]              s_rresp,
    output reg                    s_rvalid
);
    
    reg [DATA_WIDTH-1:0] reg_file [0:NUM_REGS-1];//register file

    reg [ADDR_WIDTH-1:0] wr_addr_q; //write register address

    //state parameters
    localparam WR_IDLE = 2'd0,
               WR_DATA = 2'd1,
               WR_RESP = 2'd2;
    reg [1:0] wstate; //write state register

    //write address decode
    wire    wr_address_check=(wr_addr_q[1:0]==2'b00)&&(wr_addr_q < 32'h0000_0010);
    wire [1:0]    wr_index= wr_addr_q[3:2];
    //READ address decode
    wire    rd_address_check=(s_araddr[1:0]==2'b00)&&(s_araddr < 32'h0000_0010);
    wire [1:0]    rd_index= s_araddr[3:2];

    //garantee the handshake
    assign s_awready = !reset && (wstate == WR_IDLE);
    assign s_wready  = !reset && (wstate == WR_DATA);

    wire aw_handshakeOk = s_awvalid && s_awready;
    wire w_handshakeOk  = s_wvalid  && s_wready;
    wire b_handshakeOk  = s_bvalid  && s_bready;

    assign s_arready = !reset && !s_rvalid;
    wire ar_handshake = s_arvalid && s_arready;

    //write state machine
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            wstate      <= WR_IDLE;
            s_bresp     <= 2'b00;
            s_bvalid    <= 1'b0;
            wr_addr_q   <= 0;

            for(integer m=0;m<NUM_REGS;m=m+1) begin
                reg_file[m] <= 0;
            end
        end else begin
       
            case(wstate)
                WR_IDLE: begin
                    if(aw_handshakeOk) begin
                        wr_addr_q <= s_awaddr;
                        wstate    <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if(w_handshakeOk) begin
                       if(wr_address_check) begin
                            for(integer m=0;m<DATA_WIDTH/8;m=m+1)
                                if(s_wstrb[m]) begin
                                    reg_file[wr_index][m*8 +:8] <=s_wdata[m*8 +:8];
                                end
                            s_bresp <= 2'b00;//OKAY

                        end else begin
                            s_bresp <= 2'b10;//SLVERR
                            wstate <= WR_RESP;
                            end
                        s_bvalid <= 1'b1;
                        wstate   <= WR_RESP;

                    end
                end

                WR_RESP: begin
                    if(b_handshakeOk) begin
                        s_bvalid <= 1'b0;
                        wstate   <= WR_IDLE;
                    end
                end

                default: wstate <= WR_IDLE;
            endcase
        end
    end

//read state machine
    always @(posedge clk or posedge reset) begin 
        if(reset) begin
            s_rvalid    <= 1'b0;
            s_rresp     <= 2'b00;
            s_rdata     <= 0;
        end else begin
            if(ar_handshake) begin
                s_rvalid <= 1'b1;
                if(rd_address_check) begin
                    s_rdata <= reg_file[rd_index];
                    s_rresp <= 2'b00; //OKAY
                end else begin
                    s_rdata <= 0;
                    s_rresp <= 2'b10; //SLVERR
                end
            end else if(s_rvalid && s_rready) begin
                s_rvalid <= 1'b0;
                end
            end
    end
      
endmodule 

