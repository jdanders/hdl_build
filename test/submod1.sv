module submod1 #(
    parameter NAME = "value"
  ) (
    input wire clk,
    output logic done
  );

  assign done = clk;

endmodule: submod1
