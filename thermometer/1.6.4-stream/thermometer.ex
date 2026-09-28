# Spray 1.6.4 as streams (his monad version): each domain abstraction is a
# configured Stream -> Stream function; the app builds a description, then runs it.
defmodule OffsetAndScale do
  def map(stream, offset: o, scale: s), do: Stream.map(stream, &((&1 + o) * s))
end

defmodule LowPassFilter do
  def smooth(stream, strength: k, initial: initial),
    do: Stream.scan(stream, initial, fn v, last -> last + (v - last) / k end)
end

defmodule SampleEvery do
  def sample(stream, n), do: stream |> Stream.drop(n - 1) |> Stream.take_every(n)
end

defmodule NumberToString do
  def map(stream, decimals: d), do: Stream.map(stream, &:erlang.float_to_binary(&1 / 1, decimals: d))
end

defmodule Display do
  def show(stream, label: label), do: Stream.each(stream, &IO.puts("#{label}#{&1}"))
end

defmodule Thermometer do
  def program(readings) do
    readings
    |> OffsetAndScale.map(offset: -200, scale: 0.2)
    |> LowPassFilter.smooth(strength: 10, initial: 40.0)
    |> SampleEvery.sample(10)
    |> NumberToString.map(decimals: 1)
    |> Display.show(label: "Temperature: ")
  end
end
