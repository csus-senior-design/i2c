/*
i2c Slave

Authors:  Greg M. Crist, Jr. (gmcrist@gmail.com)

Description:
  i2c Slave
*/
module i2c_slave
    #(
        parameter ADDR_BYTES = 1,
        parameter DATA_BYTES = 2,
        parameter REG_ADDR_WIDTH = 8 * ADDR_BYTES,
        parameter REG_DATA_WIDTH = 8 * DATA_BYTES
    )(
        input clk,       // System Clock
        input reset,     // Reset signal

        input  sda_in,   // SDA Input
        output sda_out,  // SDA Output
        output sda_oen,  // SDA Output Enable

        input  scl_in,   // SCL Input
        output scl_out,  // SCL Output
        output scl_oen,  // SCL Output Enable

        input [6:0] chip_addr,  // Slave Address
        input [8 * DATA_BYTES - 1:0] data_in,    // Data read from register

        output reg write_en,    // Write enable
        output reg [REG_ADDR_WIDTH - 1:0] reg_addr,  // Register address
        output reg [8 * DATA_BYTES - 1:0] data_out,  // Data to write to register

        output reg done,
        output reg busy
    );


    // State Machine States
    localparam s_idle   = 0,
              s_shift   = 1,
              s_write   = 2,
              s_send    = 3,
              s_ack     = 4,
              s_ack2    = 5,
              s_chk_ack = 6;


    // Interal registers
    reg [7:0] sr;   // Shift register
    reg [REG_DATA_WIDTH - 1:0] sr_send;

    reg [1:0] reg_bytes;
    reg [1:0] addr_bytes;

    reg [1:0] scl_count;
    reg [11:0] clk_count;

    reg sda_reg, oen_reg;
    reg writing, reading, continuing;

    reg rw_bit;
    reg nack;
    reg [6:0] chip_addr_reg;

    wire [7:0] word;
    wire [REG_DATA_WIDTH - 1:0] word_exp;
    wire [REG_ADDR_WIDTH + 8 - 1:0] reg_addr_sh;

    // used to detecing rising or falling edges of signals
    reg  sda_s, scl_s, sda_ss, scl_ss;
    wire scl_rising, scl_falling, sda_rising, sda_falling;


    // FSM state
    reg [2:0] state;


    assign scl_oen = 1'b1;
    assign scl_out = 1'b0;
    assign sda_oen = oen_reg;
    assign sda_out = sda_reg;

    assign word = {sr[6:0], sda_s};
    assign word_exp = word;

    assign reg_addr_sh = {reg_addr, word};

    // Detect rising / falling edges
    assign scl_rising  =  scl_s && ~scl_ss;
    assign scl_falling = ~scl_s &&  scl_ss;
    assign sda_rising  =  sda_s && ~sda_ss;
    assign sda_falling = ~sda_s &&  sda_ss;


    always @(posedge clk or negedge reset) begin
        if (~reset) begin
            state       <= s_idle;
            sda_reg     <= 1'b1;
            oen_reg     <= 1'b1;

            reg_bytes   <= 1'b0;
            addr_bytes  <= 1'b0;
            sr          <= 8'h01;

            data_out    <= 1'b0;
            reg_addr    <= 1'b0;
            write_en    <= 1'b0;
            rw_bit      <= 1'b0;
            sr_send     <= 1'b0;
            nack        <= 1'b0;
            done        <= 1'b0;
            busy        <= 1'b0;
        end
        else begin
            scl_s         <= scl_in;
            scl_ss        <= scl_s;
            sda_s         <= sda_in;
            sda_ss        <= sda_s;
            chip_addr_reg <= chip_addr;

            if (scl_ss && sda_falling) begin
                state       <= s_shift;
                sda_reg     <= 1'b1;
                oen_reg     <= 1'b1;

                reg_bytes   <= 1'b0;
                addr_bytes  <= 1'b0;
                sr          <= 8'h01;

                write_en    <= 1'b0;
                busy        <= 1'b1;
                done        <= 1'b0;
            end
            else if (scl_ss && sda_rising) begin
                state    <= s_idle;
                sda_reg  <= 1'b1;
                oen_reg  <= 1'b1;
                write_en <= 1'b0;
                done     <= busy ? 1'b1 : 1'b0;
            end
            else begin
                case (state)
                    s_idle: begin
                        sda_reg     <= 1'b1;
                        oen_reg     <= 1'b1;
                        reg_bytes   <= 1'b0;
                        addr_bytes  <= 1'b0;
                        sr          <= 8'h01;
                        write_en    <= 1'b0;
                        busy        <= 1'b0;
                        done        <= 1'b0;
                    end

                    s_shift: begin
                        sda_reg <= 1'b1;
                        oen_reg <= 1'b1;

                        if (scl_rising) begin
                            sr <= word;

                            if (sr[7]) begin
                                if (addr_bytes <= ADDR_BYTES) begin
                                    addr_bytes <= addr_bytes + 1'b1;

                                    // Check the i2c address and determine if the x-fer is for this slave
                                    if (addr_bytes == 2'b00) begin
                                        // Nope, go back to idle
                                        if (word[7:1] != chip_addr_reg) begin
                                            state <= s_idle;
                                            done  <= 1'b1;
                                        end
                                        else begin
                                            state   <= s_ack;
                                            rw_bit  <= word[0];
                                            sr_send <= data_in;
                                        end
                                    end
                                    else begin
                                        state    <= s_ack;
                                        reg_addr <= reg_addr_sh[REG_ADDR_WIDTH - 1:0];
                                    end
                                end
                                else begin
                                    data_out <= (data_out << 8) | word_exp;

                                    if (reg_bytes == DATA_BYTES - 1'b1) begin
                                        state      <= s_write;
                                        write_en   <= 1'b1;
                                        reg_bytes  <= reg_bytes + 1'b1 - DATA_BYTES;
                                    end
                                    else begin
                                        state      <= s_ack;
                                        reg_bytes  <= reg_bytes + 1'b1;
                                    end
                                end
                            end
                        end
                    end

                    s_write: begin
                        state    <= s_ack;
                        sda_reg  <= 1'b1;
                        oen_reg  <= 1'b1;
                        reg_addr <= reg_addr + 1'b1;
                        write_en <= 1'b0;
                    end

                    s_send: begin
                        if (scl_falling) begin
                            sr <= word;

                            if (sr[7]) begin
                                state     <= s_chk_ack;
                                sda_reg   <= 1'b1;
                                oen_reg   <= 1'b1;
                                reg_bytes <= reg_bytes + 1'b1;

                                if (reg_bytes == DATA_BYTES - 1'b1) begin
                                    reg_addr  <= reg_addr + 1'b1;
                                    reg_bytes <= 1'b0;
                                end
                            end
                            else begin
                                sda_reg <= sr_send[REG_DATA_WIDTH - 1];
                                oen_reg <= 1'b0;
                                sr_send <= sr_send << 1;
                            end
                        end
                    end

                    s_ack: begin
                        write_en <= 0;

                        if (~scl_ss) begin
                            state   <= s_ack2;
                            sda_reg <= 1'b0;
                            oen_reg <= 1'b0;

                            if (rw_bit && (reg_bytes == 0)) begin
                                sr_send <= data_in;
                            end
                        end
                    end

                    s_ack2: begin
                        sr <= 8'h01;
                        write_en <= 0;

                        if (scl_falling) begin
                            if (rw_bit) begin
                                state   <= s_send;
                                sda_reg <= sr_send[REG_DATA_WIDTH - 1];
                                oen_reg <= 1'b0;
                                sr_send <= sr_send << 1;
                            end
                            else begin
                                state   <= s_shift;
                                sda_reg <= 1'b1;
                                oen_reg <= 1'b1;
                            end
                        end
                    end

                    s_chk_ack: begin
                        sr <= 8'h01;

                        if (scl_rising) begin
                            nack <= sda_s;
                        end

                        if (scl_falling) begin
                            if (nack) begin
                                state   <= s_idle;
                                sda_reg <= 1'b1;
                                oen_reg <= 1'b1;
                                done    <= 1'b1;
                            end
                            else begin
                                state   <= s_send;
                                sda_reg <= sr_send[REG_DATA_WIDTH - 1];
                                oen_reg <= 1'b0;
                                sr_send <= sr_send << 1;
                            end
                        end
                    end
                endcase
            end
        end
    end
endmodule
