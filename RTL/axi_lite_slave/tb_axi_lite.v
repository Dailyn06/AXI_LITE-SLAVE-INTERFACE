`timescale 1ns/1ps

// Directed tests for the DUT's fixed four-register, 32-bit configuration.
module tb_axi_lite;
    localparam CLK_PERIOD = 10;
    localparam TIMEOUT = 100;
    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    reg reset;
    reg [31:0] awaddr, wdata, araddr;
    reg [3:0] wstrb;
    reg awvalid, wvalid, bready, arvalid, rready;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    reg [31:0] model [0:3];
    integer checks = 0;
    integer i, lane;

    axi_lite_slave #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .NUM_REGS(4)) u_slave (
        .clk(clk), .reset(reset),
        .s_awaddr(awaddr), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wvalid(wvalid), .s_wready(wready),
        .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_araddr(araddr), .s_arvalid(arvalid), .s_arready(arready),
        .s_rdata(rdata), .s_rresp(rresp), .s_rvalid(rvalid), .s_rready(rready)
    );

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_axi_lite);
    end

    // Drive on falling edges and sample handshakes on rising edges.
    task automatic send_aw(input [31:0] addr, input integer delay_cycles);
        integer cycles;
        begin
            repeat(delay_cycles) @(negedge clk);
            @(negedge clk);
            awaddr = addr; awvalid = 1;
            cycles = 0;
            @(posedge clk);
            while (awready !== 1'b1) begin
                cycles = cycles + 1;
                if (cycles >= TIMEOUT) $fatal(1, "AW timeout addr=%h", addr);
                @(posedge clk);
            end
            @(negedge clk);
            awvalid = 0;
            awaddr = 32'hffff_ffff; // Prove the DUT captured the accepted address.
        end
    endtask

    task automatic send_w(input [31:0] data, input [3:0] strb,
                          input integer delay_cycles);
        integer cycles;
        begin
            repeat(delay_cycles) @(negedge clk);
            @(negedge clk);
            wdata = data; wstrb = strb; wvalid = 1;
            cycles = 0;
            @(posedge clk);
            while (wready !== 1'b1) begin
                cycles = cycles + 1;
                if (cycles >= TIMEOUT) $fatal(1, "W timeout");
                @(posedge clk);
            end
            @(negedge clk);
            wvalid = 0; wdata = 0; wstrb = 0;
        end
    endtask

    task automatic axi_write(input [31:0] addr, input [31:0] data,
                             input [3:0] strb, input [1:0] expected_resp,
                             input integer aw_delay, input integer w_delay,
                             input integer stall_cycles);
        integer cycles, byte_lane;
        begin
            // Independent drivers allow data to arrive before the address.
            fork
                send_aw(addr, aw_delay);
                send_w(data, strb, w_delay);
            join
            cycles = 0;
            @(posedge clk);
            while (bvalid !== 1'b1) begin
                cycles = cycles + 1;
                if (cycles >= TIMEOUT) $fatal(1, "B timeout addr=%h", addr);
                @(posedge clk);
            end
            if (bresp !== expected_resp)
                $fatal(1, "BRESP addr=%h expected=%b actual=%b", addr, expected_resp, bresp);
            repeat(stall_cycles) begin
                @(posedge clk);
                if (bvalid !== 1'b1 || bresp !== expected_resp)
                    $fatal(1, "Write response changed while stalled");
            end
            @(negedge clk); bready = 1;
            @(posedge clk);
            if (bvalid !== 1'b1 || bresp !== expected_resp)
                $fatal(1, "Invalid write response at handshake");
            @(negedge clk); bready = 0;
            if (expected_resp == 2'b00)
                for (byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1)
                    if (strb[byte_lane])
                        model[addr >> 2][byte_lane*8 +: 8] = data[byte_lane*8 +: 8];
            checks = checks + 1;
        end
    endtask

    task automatic axi_read(input [31:0] addr, input [31:0] expected_data,
                            input [1:0] expected_resp, input integer stall_cycles);
        integer cycles;
        begin
            @(negedge clk); araddr = addr; arvalid = 1;
            cycles = 0;
            @(posedge clk);
            while (arready !== 1'b1) begin
                cycles = cycles + 1;
                if (cycles >= TIMEOUT) $fatal(1, "AR timeout addr=%h", addr);
                @(posedge clk);
            end
            @(negedge clk); arvalid = 0; araddr = 32'hffff_ffff;
            cycles = 0;
            @(posedge clk);
            while (rvalid !== 1'b1) begin
                cycles = cycles + 1;
                if (cycles >= TIMEOUT) $fatal(1, "R timeout addr=%h", addr);
                @(posedge clk);
            end
            if (rresp !== expected_resp || rdata !== expected_data)
                $fatal(1, "Read addr=%h expected=%h/%b actual=%h/%b",
                       addr, expected_data, expected_resp, rdata, rresp);
            repeat(stall_cycles) begin
                @(posedge clk);
                if (rvalid !== 1'b1 || rresp !== expected_resp || rdata !== expected_data)
                    $fatal(1, "Read response changed while stalled");
            end
            @(negedge clk); rready = 1;
            @(posedge clk);
            if (rvalid !== 1'b1 || rresp !== expected_resp || rdata !== expected_data)
                $fatal(1, "Invalid read response at handshake");
            @(negedge clk); rready = 0;
            checks = checks + 1;
        end
    endtask

    task automatic apply_reset;
        integer reg_num;
        begin
            @(negedge clk);
            reset = 1;
            awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0;
            repeat(3) @(negedge clk);
            if (bvalid !== 1'b0 || rvalid !== 1'b0)
                $fatal(1, "Reset did not clear response VALID signals");
            for (reg_num = 0; reg_num < 4; reg_num = reg_num + 1)
                model[reg_num] = 0;
            reset = 0;
        end
    endtask

    initial begin
        reset = 0;
        awaddr = 0; wdata = 0; araddr = 0; wstrb = 0;
        awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0;
        apply_reset();
        for (i = 0; i < 4; i = i + 1) axi_read(i*4, 0, 0, 0);

        // Address first, data first, and simultaneous VALID assertion.
        axi_write(0, 32'h12345678, 4'hf, 0, 0, 3, 0);
        axi_write(4, 32'h89abcdef, 4'hf, 0, 3, 0, 4);
        axi_write(8, 32'h55aa00ff, 4'hf, 0, 0, 0, 0);
        axi_write(12, 32'hdeadbeef, 4'hf, 0, 0, 0, 3);
        for (i = 0; i < 4; i = i + 1) axi_read(i*4, model[i], 0, i);

        for (lane = 0; lane < 4; lane = lane + 1) begin
            axi_write(4, 32'h10203040, 4'b0001 << lane, 0, 0, 0, 0);
            axi_read(4, model[1], 0, 1);
        end
        axi_write(4, 32'hffffffff, 4'h5, 0, 0, 2, 0);
        axi_read(4, model[1], 0, 0);
        axi_write(4, 32'h00000000, 4'h0, 0, 0, 0, 0);
        axi_read(4, model[1], 0, 0);

        // The current DUT returns zero data and SLVERR for invalid addresses.
        axi_write(16, 32'hffffffff, 4'hf, 2'b10, 0, 0, 3);
        axi_write(1, 32'hffffffff, 4'hf, 2'b10, 2, 0, 0);
        axi_read(16, 0, 2'b10, 3);
        axi_read(1, 0, 2'b10, 0);
        axi_read(32'hffff_fffc, 0, 2'b10, 0);
        for (i = 0; i < 4; i = i + 1) axi_read(i*4, model[i], 0, 0);

        // Concurrent read/write to different registers.
        fork
            axi_write(0, 32'hcafebabe, 4'hf, 0, 0, 2, 2);
            axi_read(12, model[3], 0, 4);
        join
        axi_read(0, model[0], 0, 0);

        // Reset while both response channels are pending and stalled.
        fork
            begin
                fork
                    send_aw(8, 0);
                    send_w(32'h11223344, 4'hf, 0);
                join
            end
            begin
                @(negedge clk); araddr = 12; arvalid = 1;
                @(posedge clk);
                while (arready !== 1'b1) @(posedge clk);
                @(negedge clk); arvalid = 0;
            end
        join
        @(negedge clk);
        if (bvalid !== 1'b1 || rvalid !== 1'b1)
            $fatal(1, "Expected pending responses before reset");
        apply_reset();
        for (i = 0; i < 4; i = i + 1) axi_read(i*4, 0, 0, 0);
        axi_write(0, 32'h76543210, 4'hf, 0, 2, 0, 0);
        axi_read(0, model[0], 0, 0);
        repeat(3) @(negedge clk);
        if (bvalid !== 1'b0 || rvalid !== 1'b0)
            $fatal(1, "Unexpected extra response");
        $display("PASS: %0d checked transactions", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Global watchdog timeout");
    end
endmodule
