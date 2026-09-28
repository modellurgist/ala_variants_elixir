Code.require_file("bad_thermometer.ex", __DIR__)

# Simulated ADC readings, on the scale Spray's literals expect.
readings = Enum.map(1..30, fn i -> 1 + rem(i, 3) end)
BadThermometer.process_temperatures(readings)
