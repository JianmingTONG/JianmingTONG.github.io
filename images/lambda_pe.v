`timescale 1ns / 1ps
module lambda_pe #(
    parameter THIS_PE_ID            = 0 ,   // ID/Sel for this PE
    parameter NEXT_PE_ID            = 1 ,   // ID/Sel for this PE
    parameter DATA_WIDTH            = 8 ,   //
    parameter WEIGHTS_DEPTH         = 16,   //
    parameter LOG2_WEIGHTS_DEPTH    = 4 ,   //
    parameter OUTPUT_WIDTH          = 32,   //

)(
    // timing signals
    clk,
    rst_n,

    // data signals
    i_iacts,
    i_iacts_valid,
    i_weights,
    i_weights_addr,
    i_weights_valid,
    i_iacts_zp,
    i_iacts_zp_valid,
    i_weights_zp,
    i_weights_zp_valid,

    // control signals for localbuffer+pe operation
    i_weights_ping_pong_sel,
    i_pe_sel,
    i_weights_to_use,
    i_weights_sel_for_iacts_use,

    o_iacts,
    o_iacts_valid,
    o_weights,
    o_weights_valid,

    o_out_data,
    o_out_data_valid
);


    /*
        ports
    */
    input                                   clk;
    input                                   rst_n;
    input    [DATA_WIDTH-1 : 0]             i_iacts;
    input                                   i_iacts_valid;
    input    [DATA_WIDTH-1 : 0]             i_weights;
    input    [LOG2_WEIGHTS_DEPTH-1 : 0]     i_weights_addr;
    input                                   i_weights_valid;
    input    [DATA_WIDTH-1 : 0]             i_iacts_zp;
    input                                   i_iacts_zp_valid;
    input    [DATA_WIDTH-1 : 0]             i_weights_zp;
    input                                   i_weights_zp_valid;

    input                                   i_weights_ping_pong_sel,
    input    [LOG2_WEIGHTS_DEPTH -1: 0]     i_pe_sel,
    input    [LOG2_WEIGHTS_DEPTH -1: 0]     i_weights_to_use,
    input    [LOG2_WEIGHTS_DEPTH -1: 0]     i_weights_sel_for_iacts_use,


    output   reg [DATA_WIDTH-1 : 0]         o_iacts;
    output   reg                            o_iacts_valid;
    output   reg [DATA_WIDTH-1 : 0]         o_weights;
    output   reg                            o_weights_valid;
    output   reg [OUTPUT_WIDTH - 1 : 0]     o_out_data;
    output   reg                            o_out_data_valid;
    output   reg [LOG2_WEIGHTS_DEPTH -1: 0] o_weights_sel_for_iacts_use,
    output   reg [LOG2_WEIGHTS_DEPTH -1: 0] o_pe_sel,

    /*
        inner logics
    */

    reg [DATA_WIDTH-1 : 0] r_local_weights_buffer_ping[WEIGHTS_DEPTH-1:0];
    reg [DATA_WIDTH-1 : 0] r_local_weights_buffer_pong[WEIGHTS_DEPTH-1:0];
    reg [DATA_WIDTH-1 : 0] r_iacts;
    reg [DATA_WIDTH-1 : 0] r_iacts_zp;
    reg [DATA_WIDTH-1 : 0] r_weights_zp;

    reg [2*DATA_WIDTH - 1 : 0]  r_product;
    reg [OUTPUT_WIDTH - 1 : 0]  r_sum;


    integer i;
    /*
        register the iacts, weights, zp data
        store and forward the iacts, weights and generate valids
    */
    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            r_iacts                         <=  0;
            r_iacts_zp                      <=  0;
            r_weights_zp                    <=  0;
            o_iacts                         <=  0;
            o_weights                       <=  0;
            o_weights_valid                 <=  0;

            for (i=0; i<WEIGHTS_DEPTH; i=i+1) 
            begin
                r_local_weights_buffer_ping[i]   <= 0;
                r_local_weights_buffer_pong[i]   <= 0;
            end
        end
        else
        begin
            if(i_iacts_valid == 1)
            begin
                r_iacts         <=  i_iacts;
                o_iacts         <=  i_iacts;
                o_iacts_valid   <=  1;
            end
            else
            begin
                o_iacts_valid   <=  0;
            end

            if(i_iacts_zp_valid == 1)
            begin
                r_iacts_zp      <=  i_iacts_zp;
            end
            
            if(i_weights_zp_valid == 1)
            begin
                r_weights_zp    <=  i_weights_zp;
            end

            if(i_weights_valid == 1)
            begin
                if(i_pe_sel == THIS_PE_ID)
                begin
                    if(i_weights_ping_pong_sel == 0)
                    begin
                        r_local_weights_buffer_ping[i_weights_addr] <=  i_weights;
                    end
                    else
                    begin
                        r_local_weights_buffer_pong[i_weights_addr] <=  i_weights;
                    end
                    o_pe_sel                                        <=  NEXT_PE_ID;         //%% check this
                end
                else
                begin
                    o_pe_sel                                        <=  i_pe_sel;           //%% check this
                end
                o_weights       <=  i_weights;
                o_weights_valid <=  1;
            end
            else
            begin
                o_weights_valid <=  0;
            end
        end
    end


    reg     [DATA_WIDTH-1 : 0] r_temp_weight;
    wire    [DATA_WIDTH   : 0] w_iacts_sub_zp       =   {0,r_iacts} - {0,r_iacts_zp};
    wire    [DATA_WIDTH   : 0] w_weights_sub_zp     =   {0,r_temp_weight} - {0,r_weights_zp};


    /*
        MAC for the weights and iacts logic
    */
    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            o_out_data                      <=  0;
            o_out_data_valid                <=  0;
            r_sum                           <=  0;
            r_product                       <=  0;
            r_temp_weight                   <=  0;
            r_iacts_valid_d1                <=  0;
            r_iacts_valid_d2                <=  0;
        end
        else
        begin
            r_iacts_valid_d1   <=  i_iacts_valid;
            r_iacts_valid_d2   <=  r_iacts_valid_d1;
            r_iacts_valid_d3   <=  r_iacts_valid_d2;
            if(r_iacts_valid_d1 == 1)
            begin
                if(i_weights_ping_pong_sel == 1)
                begin
                    r_temp_weight   <=  r_local_weights_buffer_ping[i_weights_sel_for_iacts_use]      //d2
                end
                else
                begin
                    r_temp_weight   <=  r_local_weights_buffer_pong[i_weights_sel_for_iacts_use]      //d2
                end
            end

            r_product   <=  w_iacts_sub_zp * w_weights_sub_zp;  //d3

            if(r_iacts_valid_d3 == 1)
            begin
                if(i_weights_sel_for_iacts_use != i_weights_to_use)
                begin
                    r_sum   <= r_sum + r_product;
                end
                else
                begin
                    o_out_data          <=  r_sum;
                    o_out_data_valid    <=  1;
                    r_sum               <=  0;
                end
            end
            else
            begin
                o_out_data_valid        <=  0;
            end

        end

    end




endmodule
