module mod1 (input wire clk, input wire data, output logic result);
  `include "my_incl.svh"
  import pkg1::*;
  typedef logic [1:0] pipe_t;
  logic out;
  pipe_t my_pipe;
  always_ff @(posedge clk) my_pipe <= pkg2::data_to_pipe(data);
  submod1 #(.NAME("module")) mod1 (.clk(my_pipe[0]), .done(out));
  submod2 mod2 (out, result);
endmodule
