`timescale 1ns / 1ps
/*
----------------------------------------
Stereoscopic Vision System
Senior Design Project - Team 11
California State University, Sacramento
Spring 2015 / Fall 2015
----------------------------------------

%MODULE_TITLE%

Authors:  %AUTHOR% (%AUTHOR_EMAIL%)

Description:
  %MODULE_DESCRIPTION%
*/
module i2c_tb ();
    parameter CLOCKPERIOD = 20;
    parameter CHIP_ADDR = 7'h0F;

    // for counting the cycles
    reg [15:0] cycle;

    reg reset;
    reg clock;

    // For storing slave data
    reg [15:0]  slave_data[0:255];

    wire SDA, SCL;
    wire [11:0] clk_div = 100;

    reg  [6:0]  master_chip_addr;
    reg  [7:0]  master_reg_addr;

    wire [3:0]  master_status;
    wire        master_done;
    wire        master_busy;

    reg         master_write_en;
    reg         master_read_en;
    reg  [15:0] master_data_in;
    wire [15:0] master_data_out;

    wire        master_sda_out;
    wire        master_sda_oen;
    wire        master_scl_out;
    wire        master_scl_oen;

    reg  [6:0]  slave_chip_addr;
    wire [7:0]  slave_reg_addr;

    wire        slave_busy;
    wire        slave_done;

    wire        slave_write_en;
    reg  [15:0] slave_data_in;
    wire [15:0] slave_data_out;

    wire        slave_sda_in;
    wire        slave_scl_in;

    wire        slave_sda_out;
    wire        slave_sda_oen;
    wire        slave_scl_out;
    wire        slave_scl_oen;

    reg         write_mode;

    assign SDA = master_sda_oen ? 1'bz : master_sda_out;
    assign SDA = slave_sda_oen  ? 1'bz : slave_sda_out ;
    assign SCL = master_scl_oen ? 1'bz : master_scl_out;
    assign SCL = slave_scl_oen  ? 1'bz : slave_scl_out ;

    pullup(SDA);
    pullup(SCL);

    // i2c Master
    i2c_master #(
        .ADDR_BYTES(1),
        .DATA_BYTES(2)
    ) i2c_master (
        .clk        (clock),
        .reset      (reset),
        .clk_div    (clk_div),

        .open_drain (1'b1),

        .chip_addr  (master_chip_addr),
        .reg_addr   (master_reg_addr),
        .data_in    (master_data_in),
        .write_en   (master_write_en),
        .write_mode (write_mode),
        .read_en    (master_read_en),
        .status     (master_status),
        .done       (master_done),
        .busy       (master_busy),
        .data_out   (master_data_out),

        .sda_in     (SDA),
        .scl_in     (SCL),
        .sda_out    (master_sda_out),
        .sda_oen    (master_sda_oen),
        .scl_out    (master_scl_out),
        .scl_oen    (master_scl_oen)
    );

    // i2c Slave
    i2c_slave #(
        .ADDR_BYTES(1),
        .DATA_BYTES(2)
    ) i2c_slave (
        .clk        (clock),
        .reset      (reset),

        .open_drain (1'b1),

        .chip_addr  (slave_chip_addr),
        .reg_addr   (slave_reg_addr),
        .data_in    (slave_data_in),
        .write_en   (slave_write_en),
        .data_out   (slave_data_out),
        .done       (slave_done),
        .busy       (slave_busy),

        .sda_in     (SDA),
        .scl_in     (SCL),
        .sda_out    (slave_sda_out),
        .sda_oen    (slave_sda_oen),
        .scl_out    (slave_scl_out),
        .scl_oen    (slave_scl_oen)
    );

    // Initial conditions; setup
    initial begin
        $timeformat(-9,1, "ns", 12);

        // Initial Conditions
        cycle <= 0;
        reset <= 1'b0;

        slave_chip_addr  <= CHIP_ADDR;

        master_chip_addr <= 8'h00;
        master_reg_addr  <= 8'h00;
        master_data_in   <= 16'h0000;
        master_write_en  <= 1'b0;
        master_read_en   <= 1'b0;

        // multibyte
        write_mode       <= 1'b0;

        // Initialize clock
        #2
        clock <= 1'b0;

        // Deassert reset
        #5
        reset <= 1'b1;

        $display("Beginning write/read tests");

        #100 write_read(CHIP_ADDR, 8'h00, 16'hCAFE);
        #100 write_read(CHIP_ADDR, 8'h0A, 16'hBEEF);
        #100 write_read(CHIP_ADDR, 8'h10, 16'hD0D0);
        #100 write_read(CHIP_ADDR, 8'h1A, 16'h3E3E);

        #100 read_i2c(CHIP_ADDR, 8'h00);
        if (master_data_out == 16'hCAFE) begin
            $display("PASS: delayed read");
        end
        else begin
            $display("FAIL: delayed read");
        end

//        $writememh("regdata.hex", slave_data);

        #100 $finish;
    end

    // Save slave data to register
    always @ (posedge clock) begin
        if (slave_write_en) begin
            $display("Writing to slave reg=%x data=%x", slave_reg_addr, slave_data_out);
            slave_data[slave_reg_addr] <= slave_data_out;
        end

        slave_data_in <= slave_data[slave_reg_addr];
    end

    task write_read;
        input [6:0]  chip_addr;
        input [7:0]  reg_addr;
        input [15:0] data;

        begin
            write_i2c(chip_addr, reg_addr, data);
            read_i2c(chip_addr, reg_addr);

            if (master_data_out == data) begin
                $display("PASS: write=%x | read=%x", data, master_data_out);
            end
            else begin
                $display("FAIL: write=%x | read=%x", data, master_data_out);
            end
        end
    endtask

    task write_i2c;
        input [6:0]  chip_addr;
        input [7:0]  reg_addr;
        input [15:0] data;

        begin
            @ (posedge clock) begin
                master_write_en  = 1'b1;

                master_chip_addr = chip_addr;
                master_reg_addr  = reg_addr;
                master_data_in   = data;
            end

            @ (posedge clock)
                master_write_en = 1'b0;

            @ (posedge clock);

            while (master_busy) begin
                @ (posedge clock);
            end
        end
    endtask

    task read_i2c;
        input [6:0] chip_addr;
        input [7:0] reg_addr;

        begin
            @ (posedge clock) begin
                master_chip_addr = chip_addr;
                master_reg_addr  = reg_addr;
                master_read_en   = 1'b1;
            end

            @ (posedge clock) begin
                master_read_en = 1'b0;
            end

            @ (posedge clock);

            while (master_busy) begin
                @ (posedge clock);
            end
        end
    endtask


/**************************************************************/
/* The following can be left as-is unless necessary to change */
/**************************************************************/

    // Cycle Counter
    always @ (posedge clock)
        cycle <= cycle + 1;

    // Clock generation
    always #(CLOCKPERIOD / 2) clock <= ~clock;

/*
  Conditional Environment Settings for the following:
    - Icarus Verilog
    - VCS
    - Altera Modelsim
    - Xilinx ISIM
*/
// Icarus Verilog
`ifdef IVERILOG
    initial $dumpfile("vcdbasic.vcd");
    initial $dumpvars();
`endif

// VCS
`ifdef VCS
    initial $vcdpluson;
`endif

// Altera Modelsim
`ifdef MODEL_TECH
`endif

// Xilinx ISIM
`ifdef XILINX_ISIM
`endif
endmodule
