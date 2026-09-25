# The ALA thermometer from the intro blog post, in one file: four generic
# domain abstractions (OffsetAndScale, LowPassFilter, SampleEvery, Display) and
# a Thermometer composition that wires them and holds the application literals.
# `mix ala.lint` (with a layer map putting Thermometer at the top and the rest
# below) scores this 100/100 at the default and --strict levels; only the
# aspirational --super-strict R11 flags push_reading's two nil-guards.

defmodule OffsetAndScale do
  defstruct [:offset, :scale]
  def apply(%__MODULE__{offset: o, scale: s}, value), do: (value + o) * s
end

defmodule LowPassFilter do
  defstruct [:strength, :last_output]

  def smooth(%__MODULE__{} = f, input) do
    output = f.last_output + (input - f.last_output) / f.strength
    {output, %{f | last_output: output}}
  end
end

defmodule SampleEvery do
  defstruct [:n, count: 0]

  def tick(%__MODULE__{n: n, count: c} = s, value) do
    c = c + 1
    if c >= n, do: {value, %{s | count: 0}}, else: {nil, %{s | count: c}}
  end
end

defmodule Display do
  defstruct [:label, :units, :last]
  def record(%__MODULE__{} = d, value), do: %{d | last: value}
end

defmodule Thermometer do
  defstruct [:oas, :lpf, :sample, :display]

  def new(opts \\ []) do
    %__MODULE__{
      oas: %OffsetAndScale{offset: -200, scale: 0.2},
      lpf: %LowPassFilter{strength: 10, last_output: Keyword.get(opts, :lpf_initial, 400.0)},
      sample: %SampleEvery{n: 10},
      display: %Display{label: "Temperature", units: "C"}
    }
  end

  def push_reading(%__MODULE__{} = therm, reading) do
    scaled = OffsetAndScale.apply(therm.oas, reading)
    {smoothed, lpf} = LowPassFilter.smooth(therm.lpf, scaled)
    {sampled, sample} = if smoothed, do: SampleEvery.tick(therm.sample, smoothed), else: {nil, therm.sample}
    display = if sampled, do: Display.record(therm.display, sampled), else: therm.display
    %{therm | lpf: lpf, sample: sample, display: display}
  end
end
