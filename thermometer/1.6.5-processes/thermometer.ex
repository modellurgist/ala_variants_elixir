# Spray §1.6.5 with processes: each instance is a process with an output port,
# wired from above.
defmodule Thermometer do
  def start do
    program = Stage.new(%OffsetAndScale{offset: -200, scale: 0.2})

    program
    |> Stage.wire_in(Stage.new(%LowPassFilter{strength: 10, last: 40.0}))
    |> Stage.wire_in(Stage.new(%SampleEvery{n: 10}))
    |> Stage.wire_in(Stage.new(%NumberToString{decimals: 1}))
    |> Stage.wire_in(Stage.new(%Display{label: "Temperature: "}))

    program
  end
end
