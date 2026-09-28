Code.require_file("thermometer.ex", __DIR__)

# Simulated ADC readings; a real source would be a stream that reads the channel on each pull.
readings = Stream.map(1..30, fn i -> 400 + rem(i, 7) end)
Stream.run(Thermometer.program(readings))
