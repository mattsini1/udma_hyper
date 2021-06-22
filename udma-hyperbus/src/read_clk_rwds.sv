// Copyright 2018-2021 ETH Zurich and University of Bologna.
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

//// Hayate Okuhara <hayate.okuhara@unibo.it>

// Description: Connection between HyperBus and Read CDC FIFO
`timescale 1 ps/1 ps

module read_clk_rwds #(
    parameter  DELAY_BIT_WIDTH = 3
)(
    input logic                    clk0,
    input logic                    rst_ni,   // Asynchronous reset active low

    input  logic                   clk_test,
    input  logic                   test_en_ti,

    input logic [1:0]                 mem_sel_i,
    input logic [DELAY_BIT_WIDTH-1:0] config_t_rwds_delay_line,

    input logic                    hyper_rwds_i,
    input logic [15:0]             hyper_dq_i,
    input logic                    read_clk_en_i,
    input logic                    en_ddr_in_i,
    input logic                    ready_i, //Clock to FIFO

    output logic                   valid_o,
    output logic [31:0]            data_o
);

    logic resetReadModule;
    logic hyper_rwds_i_d;
    logic clk_rwds;
    logic clk_rwds_n;
    logic clk_rwds_orig;
    logic [15:0] data_pedge;
    logic [31:0] data_fifoin;

    logic cdc_input_fifo_ready;
    logic read_in_valid;
    logic clk_rwds_inverter;

   logic  clk0_gated;
   
   
    //Delay of rwds for center aligned read
    hyperbus_delay_line #(
        .BIT_WIDTH     ( DELAY_BIT_WIDTH          )
    )hyperbus_delay_line_i(
        .in            ( hyper_rwds_i             ),
        .out           ( hyper_rwds_i_d           ),
        .delay         ( config_t_rwds_delay_line )
    );

    pulp_clock_gating clk_rwds_origin_clk_gate (
           .clk_i     ( hyper_rwds_i_d  ),
           .en_i      ( read_clk_en_i  ),
           .test_en_i ( 1'b0  ),
           .clk_o     ( clk_rwds_orig )
       );

    pulp_clock_gating clk_0_gate (
           .clk_i     ( clk0           ),
           .en_i      ( read_clk_en_i  ),
           .test_en_i ( 1'b0           ),
           .clk_o     ( clk0_gated     )
       );
   
    pulp_clock_mux2 ddrmux (
        .clk_o     ( clk_rwds      ),
        .clk0_i    ( 1'b0          ),
        .clk1_i    ( clk_rwds_orig ),
        .clk_sel_i ( read_clk_en_i )
    );


    assign resetReadModule = ~rst_ni || (~read_clk_en_i && ~test_en_ti);

    always_ff @(posedge clk_rwds or posedge resetReadModule) begin : proc_read_in_valid
        if(resetReadModule) begin
            read_in_valid <= 0;
        end else begin
            read_in_valid <= 1;
        end
    end

    always @(posedge clk_rwds or posedge resetReadModule)
      begin
        if(resetReadModule)
          data_pedge <= 0;
        else
          data_pedge <= hyper_dq_i;
      end

    assign data_fifoin = read_in_valid ? ( (mem_sel_i==2'b11) ? {data_pedge, hyper_dq_i} : {16'b0, data_pedge[7:0], hyper_dq_i[7:0]} ) : 32'b0;



    `ifndef SYNTHESIS
    always @(negedge cdc_input_fifo_ready) begin
        assert(cdc_input_fifo_ready) else $error("FIFO i_cdc_fifo_hyper should always be ready");
    end
    `endif

    pulp_clock_inverter clk_inv_rwds
    (
      .clk_i(clk_rwds),
      .clk_o(clk_rwds_inverter)
    );


    udma_dc_fifo_hyper  #(.DATA_WIDTH(32), .BUFFER_DEPTH(16)) 
    i_cdc_fifo_hyper ( 
      .src_rstn_i  ( rst_ni               ), 
      .src_clk_i   ( clk_rwds_inverter    ), 
      .src_data_i  ( data_fifoin          ), 
      .src_valid_i ( read_in_valid        ), 
      .src_ready_o ( cdc_input_fifo_ready ), 
 
      .dst_rstn_i  ( rst_ni               ), 
      .dst_clk_i   ( clk0_gated           ), 
      .dst_data_o  ( data_o               ), 
      .dst_valid_o ( valid_o              ), 
      .dst_ready_i ( ready_i              ) 
    ); 
    

endmodule
