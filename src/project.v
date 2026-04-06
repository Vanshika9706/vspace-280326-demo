`timescale 1ns / 1ps
`default_nettype none

module tt_um_AnjaniKad_medical_bms (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    wire [3:0] voltage    = ui_in[3:0];
    wire [1:0] current    = ui_in[5:4];
    wire       temp_flag  = ui_in[6];
    wire       safe_reset = ui_in[7];

    wire valid_voltage = (voltage != 4'd0);

wire volt_crit = valid_voltage &&
                 ((voltage <= 4'd1) | (voltage >= 4'd14));

wire volt_warn = valid_voltage &&
                 ((voltage == 4'd2)  | (voltage == 4'd3) |
                  (voltage == 4'd12) | (voltage == 4'd13));
    wire volt_normal = valid_voltage && ~volt_crit & ~volt_warn;

    reg [1:0] soc;
    always @(*) begin
        if      (voltage <= 4'd1)  soc = 2'b00;
        else if (voltage <= 4'd4)  soc = 2'b01;
        else if (voltage <= 4'd10) soc = 2'b10;
        else                       soc = 2'b11;
    end

    wire curr_warn = (current == 2'b01);
    wire curr_crit = current[1];

    // --- Consolidated sequential block for GL reliability ---
    reg thermal_latch;
    reg [2:0] hyst_cnt;
    reg [3:0] wdog_cnt;
    reg [1:0] state, next_state;

    wire any_crit = volt_crit | curr_crit | thermal_latch;
    wire any_warn = volt_warn | curr_warn;
    wire all_safe = volt_normal & ~curr_crit & ~curr_warn & ~thermal_latch;

    localparam IDLE     = 2'b00;
    localparam WARN     = 2'b01;
    localparam FAULT    = 2'b10;
    localparam SHUTDOWN = 2'b11;

    wire hyst_done  = (hyst_cnt == 3'd7);
    wire wdog_fired = (wdog_cnt == 4'd15);

    // Single clocked block — all regs reset together, GL-safe
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            thermal_latch <= 1'b0;
            hyst_cnt      <= 3'd0;
            wdog_cnt      <= 4'd0;
        end else  begin
            // FSM state
            state <= next_state;

            // Thermal latch
            if (temp_flag)
                thermal_latch <= 1'b1;
            else if (safe_reset && !temp_flag)
                thermal_latch <= 1'b0;

            // Hysteresis counter
            if ((state == WARN) && all_safe)
                hyst_cnt <= hyst_cnt + 3'd1;
            else
                hyst_cnt <= 3'd0;

            // Watchdog counter
            if (state == FAULT)
                wdog_cnt <= wdog_fired ? wdog_cnt : (wdog_cnt + 4'd1);
            else
                wdog_cnt <= 4'd0;
        end
    end

    // Combinational next-state logic
    always @(*) begin
	next_state= IDLE;
        case (state)
            IDLE: begin
                if      (any_crit)               next_state = FAULT;
                else if (any_warn)               next_state = WARN;
                else                             next_state = IDLE;
            end
            WARN: begin
                if      (any_crit)               next_state = FAULT;
                else if (hyst_done && all_safe)  next_state = IDLE;
                else                             next_state = WARN;
            end
            FAULT: begin
                if      (wdog_fired)             next_state = SHUTDOWN;
                else if (safe_reset && all_safe) next_state = IDLE;
                else                             next_state = FAULT;
            end
            SHUTDOWN: begin
                if (safe_reset && all_safe)      next_state = IDLE;
                else                             next_state = SHUTDOWN;
            end
            default:                             next_state = IDLE;
        endcase
    end

    // --- OUTPUTS (MATCH TESTBENCH FORMAT) ---
wire fault    = (state != IDLE);
wire shutdown = (state == SHUTDOWN);
wire thermal  = thermal_latch;
wire overcurr = curr_crit;

assign uo_out[0]   = fault;
assign uo_out[1]   = shutdown;
assign uo_out[2]   = thermal;
assign uo_out[4:3] = state;
assign uo_out[6:5] = soc;
assign uo_out[7]   = overcurr;  

endmodule
