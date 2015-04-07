/*
i2c Master

Authors:  Greg M. Crist, Jr. (gmcrist@gmail.com)

Description:
  i2c Master
*/
module i2c_master
    #(
        parameter ADDR_BYTES = 1,
        parameter DATA_BYTES = 2,
        parameter REG_ADDR_WIDTH = 8 * ADDR_BYTES
    )(
        input  clk,            // System clock
        input  reset,          // Reset signal
        input  [11:0] clk_div, // Clock divider value to configure SCL from the system clock

        input  sda_in,   // SDA Input
        output sda_out,  // SDA Output
        output sda_oen,  // SDA Output Enable

        input  scl_in,   // SCL Input
        output scl_out,  // SCL Output
        output scl_oen,  // SCL Output Enable

        input [6:0] chip_addr, // Slave Address
        input [REG_ADDR_WIDTH - 1:0] reg_addr, // Register address

        input write_en,    // Write enable
        input write_mode,  // Write mode (0: single, 1: multi-byte)
        input read_en,     // Read enable

        output reg [8 * DATA_BYTES - 1:0] data_out,   // Data to write to register
        input [8 * DATA_BYTES - 1:0] data_in,         // Data read from register

        output reg [ST_WIDTH - 1:0] status,
        output reg done,
        output reg busy
    );

    localparam ST_WIDTH = 1 + ADDR_BYTES + DATA_BYTES;
    localparam SR_WIDTH = 8 * ST_WIDTH;

    // State Machine States
    localparam s_idle         = 0,
               s_start_write  = 1,
               s_start_read   = 2,
               s_stop         = 3,
               s_shift_out    = 4,
               s_shift_in     = 5,
               s_send_ack     = 6,
               s_send_nack    = 7,
               s_rcv_ack      = 8;


    // Interal registers
    reg [SR_WIDTH-1:0] sr;   // Shift register
    reg [5:0] sr_count;      // Location within shift register

    wire [2:0] byte_count;

    reg [1:0] scl_count;
    reg [11:0] clk_count;

    reg sda_reg, oen_reg, sda_s, scl_s;
    reg writing, reading, in_prog;

    // FSM state
    reg [3:0] state;

    assign sda_out = sda_reg;
    assign sda_oen = oen_reg;
    assign scl_out = scl_count[1];
    assign scl_oen = 0;
    assign byte_count = sr_count[5:3];

    always @ (posedge clk or negedge reset) begin
        if (~reset) begin
            state     <= s_idle;

            sda_reg   <= 1'b1;
            oen_reg   <= 1'b1;

            sr_count  <= 6'b00_0000;
            sr        <= 24'hFFF;

            writing   <= 1'b1;
            reading   <= 1'b0;
            in_prog   <= 1'b0;

            status    <= 1'b0;
            done      <= 1'b0;
            busy      <= 1'b0;

            data_out  <= 1'b0;

            scl_count <= 2'b10;
            clk_count <= 12'b0000_0000_0000;
        end
        else begin
            sda_s <= sda_in;
            scl_s <= scl_in;

            if (state == s_idle) begin
                done <= 1'b0;
                sr_count <= 6'b00_0000;

                if (~write_mode) begin
                    in_prog <= 1'b0;

                    if (in_prog) begin
                        state <= s_stop;
                        sda_reg <= 1'b0;
                        oen_reg <= 1'b0;
                    end
                    else begin
                        sda_reg <= 1'b1;
                        oen_reg <= 1'b1;
                        clk_count <= 0;
                    end
                end

                if (in_prog) begin
                    scl_count <= 2'b00;

                    sr <= {data_in, {SR_WIDTH - 8 * DATA_BYTES{1'b0}}};
                end
                else begin
                    scl_count <= 2'b10;

                    if (ADDR_BYTES == 0) begin
                        sr <= {chip_addr, 1'b0, data_in};
                    end
                    else begin
                        sr <= {chip_addr, 1'b0, reg_addr, data_in};
                    end
                end

                if (write_en) begin
                    state   <= in_prog ? s_shift_out : s_start_write;
                    writing <= 1'b1;
                    status  <= 1'b0;
                    busy    <= 1'b1;
                end
                else if (read_en) begin
                    state    <= ADDR_BYTES == 0 ? s_start_read : s_start_write;
                    writing  <= 1'b0;
                    reading  <= 1'b0;
                    status   <= 1'b0;
                    busy     <= 1'b1;
                end
                else begin
                    busy     <= 1'b0;
                end
            end
            else begin
                if (clk_count == clk_div) begin
                    clk_count <= 2'b00;
                    scl_count <= scl_count + 1'b1;

                    case (state)
                        s_start_write: begin
                            state   <= s_shift_out;
                            sda_reg <= 0;
                            oen_reg <= 0;
                        end

                        s_start_read: begin
                            if (scl_count == 2'b10) begin
                                state    <= s_shift_out;
                                sda_reg  <= 1'b0;
                                oen_reg  <= 1'b0;
                                sr       <= {chip_addr, 1'b1, {8 * (ADDR_BYTES + DATA_BYTES){1'b0}}};
                                sr_count <= 6'b00_0000;
                                reading  <= 1'b1;
                            end
                        end

                        s_stop: begin
                            if (scl_count == 2'b10) begin
                                state   <= s_idle;
                                sda_reg <= 1'b1;
                                oen_reg <= 1'b1;
                                done    <= 1'b1;
                            end
                        end

                        s_shift_out: begin
                            if (scl_count == 2'b00) begin
                                if ((sr_count[2:0]) == 3'b000 && (|sr_count)) begin
                                    state   <= s_rcv_ack;
                                    sda_reg <= 1'b1;
                                    oen_reg <= 1'b1;
                                end
                                else begin
                                    sda_reg  <= sr[SR_WIDTH - 1];
                                    oen_reg  <= 1'b0;
                                    sr       <= {sr[SR_WIDTH - 2:0], 1'b1};
                                    sr_count <= sr_count + 1'b1;
                                end
                            end
                        end

                        s_shift_in: begin
                            if (scl_count == 2'b00) begin
                                if (sr_count == 8 * (DATA_BYTES + 1)) begin
                                    state   <= s_send_nack;
                                    sda_reg <= 1'b1;
                                    oen_reg <= 1'b1;
                                end
                                else if (sr_count[2:0] == 3'b000) begin
                                    state   <= s_send_ack;
                                    sda_reg <= 1'b0;
                                    oen_reg <= 1'b0;
                                end
                            end
                            else if (scl_count == 2'b01) begin
                                data_out <= {data_out[8 * DATA_BYTES - 2:0], sda_s};
                                sda_reg  <= 1'b1;
                                oen_reg  <= 1'b1;
                                sr_count <= sr_count + 1'b1;
                            end
                        end

                        s_send_ack: begin
                            if (scl_count == 2'b00) begin
                                state   <= s_shift_in;
                                sda_reg <= 1'b1;
                                oen_reg <= 1'b1;
                            end
                            else if (scl_count == 2'b01) begin
                                status <= {status[ST_WIDTH - 2:0], sda_s};
                            end
                        end

                        s_send_nack: begin
                            if (scl_count == 2'b00) begin
                                state   <= s_stop;
                                sda_reg <= 1'b0;
                                oen_reg <= 1'b0;
                            end
                            else begin
                                sda_reg <= 1'b1;
                                oen_reg <= 1'b1;
                            end
                        end

                        s_rcv_ack: begin
                            if (scl_count == 2'b00) begin
                                if (writing && ((byte_count == DATA_BYTES + ADDR_BYTES + 1 && ~in_prog) || (byte_count == DATA_BYTES && in_prog))) begin
                                    if (write_mode) begin
                                        state   <= s_idle;
                                        in_prog <= 1'b1;
                                        done    <= 1'b1;
                                    end else begin
                                        state   <= s_stop;
                                        sda_reg <= 1'b0;
                                        oen_reg <= 1'b0;
                                    end
                                end
                                else if (~writing && ~reading && (byte_count == ADDR_BYTES + 1)) begin
                                    state <= s_start_read;
                                end
                                else if (~writing && reading) begin
                                    state <= s_shift_in;
                                end
                                else begin
                                    state    <= s_shift_out;
                                    sda_reg  <= sr[SR_WIDTH - 1];
                                    oen_reg  <= 1'b0;
                                    sr       <= {sr[SR_WIDTH - 2:0], 1'b1};
                                    sr_count <= sr_count + 1'b1;
                                end
                            end
                            else if (scl_count == 2'b01) begin
                                status <= {status[ST_WIDTH - 2:0], sda_s};
                            end
                        end
                    endcase
                end
                else begin
                    if (scl_count[1] == 1'b0 || scl_s == 1'b1) begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
            end
        end
    end
endmodule
