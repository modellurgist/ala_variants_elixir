# Spray §1.6.5 without processes: a graph of named instances, wired by the app and run
# by Circuit. The sampler fans out to the display and to a high-temperature tracker.
defmodule Thermometer do
  def circuit do
    Circuit.new(
      adc: %OffsetAndScale{offset: -200, scale: 0.2},
      filter: %LowPassFilter{strength: 10, last: 40.0},
      sample: %SampleEvery{n: 10},
      format: %NumberToString{decimals: 1},
      display: %Display{label: "Temperature: "},
      high: %Maximum{},
      high_format: %NumberToString{decimals: 1},
      high_display: %Display{label: "High: "}
    )
    |> Circuit.wire(:adc, :filter)
    |> Circuit.wire(:filter, :sample)
    |> Circuit.wire(:sample, :format)
    |> Circuit.wire(:format, :display)
    |> Circuit.wire(:sample, :high)
    |> Circuit.wire(:high, :high_format)
    |> Circuit.wire(:high_format, :high_display)
  end
end
