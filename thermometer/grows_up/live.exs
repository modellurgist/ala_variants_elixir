# Spray 1.6.6 in LiveView: HEEx nesting is the "display inside" wiring, assigns are
# where the dataflow lands, and CircuitRunner pushes results into them.
Mix.install([{:phoenix_live_view, "~> 1.0"}])
Code.require_file("circuit.exs", __DIR__)

defmodule Widgets do
  use Phoenix.Component

  slot :inner_block, required: true
  def window(assigns), do: ~H'<section class="window"><%= render_slot(@inner_block) %></section>'

  attr :text, :string, required: true
  def label(assigns), do: ~H"<span><%= @text %></span>"

  attr :value, :string, required: true
  def float_field(assigns), do: ~H"<output><%= @value %></output>"
end

# Paradigm layer: runs a circuit held in assigns and applies what reaches its edge.
defmodule CircuitRunner do
  import Phoenix.Component, only: [assign: 3]

  def feed(socket, input, data) do
    {program, outs} = Circuit.push(socket.assigns.program, input, data)

    Enum.reduce(outs, assign(socket, :program, program), fn {:assign, key, value}, socket ->
      assign(socket, key, value)
    end)
  end
end

defmodule Thermometer do
  def circuit do
    Circuit.new(
      adc: %OffsetAndScale{offset: -200, scale: 0.2},
      filter: %LowPassFilter{strength: 10, last: 40.0},
      sample: %SampleEvery{n: 10},
      format: %NumberToString{decimals: 1},
      temperature: %ToAssign{key: :temperature},
      high: %Maximum{},
      high_format: %NumberToString{decimals: 1},
      high_temperature: %ToAssign{key: :high}
    )
    |> Circuit.wire(:adc, :filter)
    |> Circuit.wire(:filter, :sample)
    |> Circuit.wire(:sample, :format)
    |> Circuit.wire(:format, :temperature)
    |> Circuit.wire(:filter, :high)
    |> Circuit.wire(:high, :high_format)
    |> Circuit.wire(:high_format, :high_temperature)
  end
end

defmodule ThermometerLive do
  use Phoenix.LiveView
  import Widgets

  def mount(_params, _session, socket) do
    {:ok, assign(socket, program: Thermometer.circuit(), temperature: "--", high: "--")}
  end

  def handle_info({:adc, reading}, socket), do: {:noreply, CircuitRunner.feed(socket, :adc, reading)}

  def render(assigns) do
    ~H"""
    <.window>
      <.label text="Temperature:" />
      <.float_field value={@temperature} />
      <.label text="High:" />
      <.float_field value={@high} />
    </.window>
    """
  end
end

# Drive the LiveView callbacks directly with simulated readings, then render.
socket = struct(Phoenix.LiveView.Socket)
{:ok, socket} = ThermometerLive.mount(%{}, %{}, socket)

socket =
  Enum.reduce(1..30, socket, fn i, socket ->
    {:noreply, socket} = ThermometerLive.handle_info({:adc, 400 + rem(i, 7)}, socket)
    socket
  end)

IO.inspect(Map.take(socket.assigns, [:temperature, :high]))

html =
  socket.assigns
  |> ThermometerLive.render()
  |> Phoenix.HTML.Safe.to_iodata()
  |> IO.iodata_to_binary()

IO.puts(html)
