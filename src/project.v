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

    // ---------------- INPUTS ----------------
    wire [3:0] voltage    = ui_in[3:0];
    wire [1:0] current    = ui_in[5:4];
    wire       temp_flag  = ui_in[6];
    wire       safe_reset = ui_in[7];

    // ---------------- SAFE SIGNALS ----------------
    wire safe_temp = (temp_flag === 1'b1);
    wire safe_reset_sig = (safe_reset === 1'b1);

    // ---------------- VOLTAGE ----------------
    wire volt_crit =
        (voltage != 4'd0) &&
        ((voltage <= 4'd1) || (voltage >= 4'd14));

    wire volt_warn =
        (voltage != 4'd0) &&
        ((voltage == 4'd2)  || (voltage == 4'd3) ||
         (voltage == 4'd12) || (voltage == 4'd13));

    wire volt_normal =
        (voltage >= 4'd4 && voltage <= 4'd11);

    // ---------------- SOC ----------------
    wire [1:0] soc =
        (voltage <= 4'd1)  ? 2'b00 :
        (voltage <= 4'd4)  ? 2'b01 :
        (voltage <= 4'd10) ? 2'b10 :
                             2'b11;

    // ---------------- CURRENT ----------------
    wire curr_warn = (current == 2'b01);
    wire curr_crit = current[1];

    // ---------------- STATE ----------------
    reg [1:0] state, next_state;

    localparam IDLE     = 2'b00;
    localparam WARN     = 2'b01;
    localparam FAULT    = 2'b10;
    localparam SHUTDOWN = 2'b11;

    // ---------------- INTERNAL ----------------
    reg thermal_latch;
    reg [2:0] hyst_cnt;
    reg [3:0] wdog_cnt;

    wire hyst_done  = (hyst_cnt == 3'd7);
    wire wdog_fired = (wdog_cnt == 4'd15);

    // 🔥 X-SAFE LOGIC
    wire any_crit =
        (volt_crit == 1'b1) ||
        (curr_crit == 1'b1) ||
        (thermal_latch == 1'b1);

    wire any_warn =
        (volt_warn == 1'b1) ||
        (curr_warn == 1'b1);

    wire all_safe =
        (volt_normal == 1'b1) &&
        (curr_crit == 1'b0) &&
        (curr_warn == 1'b0) &&
        (thermal_latch == 1'b0);

    // ---------------- SEQUENTIAL ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            thermal_latch <= 1'b0;
            hyst_cnt      <= 3'd0;
            wdog_cnt      <= 4'd0;
        end else begin
            state <= next_state;

            // SAFE thermal latch
            if (safe_temp)
                thermal_latch <= 1'b1;
            else if (safe_reset_sig && !safe_temp)
                thermal_latch <= 1'b0;

            // hysteresis
            if ((state == WARN) && all_safe)
                hyst_cnt <= hyst_cnt + 3'd1;
            else
                hyst_cnt <= 3'd0;

            // watchdog
            if (state == FAULT)
                wdog_cnt <= wdog_fired ? wdog_cnt : (wdog_cnt + 4'd1);
            else
                wdog_cnt <= 4'd0;
        end
    end

    // ---------------- NEXT STATE ----------------
    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if      (any_crit) next_state = FAULT;
                else if (any_warn) next_state = WARN;
            end

            WARN: begin
                if      (any_crit) next_state = FAULT;
                else if (hyst_done && all_safe)
                    next_state = IDLE;
            end

            FAULT: begin
                if      (wdog_fired) next_state = SHUTDOWN;
                else if (safe_reset_sig && all_safe)
                    next_state = IDLE;
            end

            SHUTDOWN: begin
                if (safe_reset_sig && all_safe)
                    next_state = IDLE;
            end
        endcase
    end

    // ---------------- OUTPUTS ----------------
    assign uo_out[0] = (state != IDLE);
    assign uo_out[1] = (state == SHUTDOWN);
    assign uo_out[2] = thermal_latch;

    assign uo_out[3] = state[0];
    assign uo_out[4] = state[1];

    assign uo_out[5] = soc[0];
    assign uo_out[6] = soc[1];

    assign uo_out[7] = curr_crit;

endmodule
