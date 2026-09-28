Mix.install([{:phoenix_live_view, "~> 1.0"}])
Code.require_file("../shared/dataflow.ex", __DIR__)
Code.require_file("../shared/circuit.ex", __DIR__)
Code.require_file("live.ex", __DIR__)

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
