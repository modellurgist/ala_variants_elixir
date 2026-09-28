Code.require_file("../shared/dataflow.ex", __DIR__)
Code.require_file("../shared/circuit.ex", __DIR__)
Code.require_file("thermometer.ex", __DIR__)

readings = Enum.map(1..30, fn i -> 400 + rem(i, 7) end)
Enum.reduce(readings, Thermometer.circuit(), fn r, c -> c |> Circuit.push(:adc, r) |> elem(0) end)
