# Spray §1.6.4, build then run: the app lists configured instances; Chain runs them.
defmodule Thermometer do
  def program do
    Chain.new([
      %OffsetAndScale{offset: -200, scale: 0.2},
      %LowPassFilter{strength: 10, last: 40.0},
      %SampleEvery{n: 10},
      %NumberToString{decimals: 1},
      %Display{label: "Temperature: "}
    ])
  end
end
