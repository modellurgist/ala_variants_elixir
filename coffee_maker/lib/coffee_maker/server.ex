defmodule CoffeeMaker.Server do
  @moduledoc """
  OTP GenServer that runs the coffee maker polling loop.

  In production Elixir, long-running processes belong under supervision.
  This module wraps `CoffeeMaker` (a pure `Step`) with the standard OTP
  lifecycle: `start_link`, named registration, graceful stop, and runtime
  state inspection.

  ## Usage

      # Standalone
      {:ok, pid} = Server.start_link(hw: MyHardwareDriver)

      # In a supervision tree (the typical production pattern)
      children = [
        {Server, hw: MyHardwareDriver, interval_ms: 50, name: :coffee_maker}
      ]
      Supervisor.start_link(children, strategy: :one_for_one)

      # Inspect machine state at any time
      Server.state(:coffee_maker)  #=> %CoffeeMaker{state: :brewing, ...}

      # Graceful stop
      Server.stop(:coffee_maker)

  ## Crash recovery

  If the hardware driver raises during a poll cycle (sensor read failure,
  actuator write failure, etc.), the Server process crashes. The supervisor
  restarts it with a fresh `CoffeeMaker.new()` in the `:idle` state. The
  first poll cycle in idle state produces all-off hardware commands —
  boiler off, valve closed, heater off, indicator off — which is a safe
  default. No special cleanup logic is needed.

  ## ALA layering

  This module lives outside the ALA layer structure. It is OTP
  infrastructure — the bridge between the pure `Step`-based application
  logic and the BEAM runtime. The `CoffeeMaker` struct and its `Step`
  implementation contain all the domain and application logic; this
  GenServer only manages the tick-driven execution and process lifecycle.
  """

  use GenServer


  @type option ::
          {:hw, module()}
          | {:interval_ms, pos_integer()}
          | {:name, GenServer.name()}

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    hw = Keyword.fetch!(opts, :hw)
    interval_ms = Keyword.get(opts, :interval_ms, 100)
    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, {hw, interval_ms}, server_opts)
  end

  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @spec state(GenServer.server()) :: CoffeeMaker.t()
  def state(server), do: GenServer.call(server, :state)

  # --- Callbacks ---

  @impl true
  def init({hw, interval_ms}) do
    send(self(), :poll)
    {:ok, %{hw: hw, machine: CoffeeMaker.new(), interval_ms: interval_ms}}
  end

  @impl true
  def handle_info(:poll, state) do
    {_cmd, machine} = CoffeeMaker.poll(state.machine, state.hw)
    Process.send_after(self(), :poll, state.interval_ms)
    {:noreply, %{state | machine: machine}}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state.machine, state}
  end
end
