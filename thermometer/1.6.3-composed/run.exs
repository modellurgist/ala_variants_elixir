Code.require_file("thermometer.ex", __DIR__)

readings = Enum.map(1..30, fn i -> 400 + rem(i, 7) end)

Enum.reduce(readings, Thermometer.new(), fn reading, therm ->
  next = Thermometer.push_reading(therm, reading)
  if next.display.last != therm.display.last, do: IO.puts("Temperature: #{Float.round(next.display.last, 1)} C")
  next
end)
