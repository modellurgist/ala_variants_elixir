Code.require_file("../shared/dataflow.ex", __DIR__)
Code.require_file("thermometer.ex", __DIR__)

# Simulated ADC readings.
readings = Enum.map(1..30, fn i -> 400 + rem(i, 7) end)
Thermometer.program() |> Chain.run(readings)
