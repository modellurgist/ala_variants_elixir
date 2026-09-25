defmodule CoffeeMakerWeb.CoffeeLive do
  @moduledoc """
  Application layer: LiveView for the Mark IV Special coffee maker.

  This module is the only place where the CoffeeMaker (application logic),
  SimulatedHardware (physical model), and Phoenix LiveView (UI framework)
  meet. It wires them together and maps user events to simulation actions.

  ## ALA layering

  The LiveView is an Application-layer module — analogous to `Server`,
  but with a UI rendering concern. It depends downward on:

    - `CoffeeMaker` (Application — the Step-based machine logic)
    - `SimulatedHardware` (Foundation — physical world model)
    - `SensorReading`, `HardwareCommand` (Foundation — I/O boundary data)
    - Phoenix LiveView (Foundation — UI framework)

  Domain abstractions (`Boiler`, `UserInterface`, `WarmerPlate`) are never
  referenced here — they're internal to `CoffeeMaker`. The LiveView
  calls `CoffeeMaker.tick/2` — a domain-named function that takes a
  `SensorReading` and returns a `HardwareCommand`.
  """

  use CoffeeMakerWeb, :live_view

  alias CoffeeMaker.Foundation.SimulatedHardware

  @tick_ms 500

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_tick()

    {:ok,
     assign(socket,
       page_title: "Coffee Maker",
       machine: CoffeeMaker.new(),
       sim: SimulatedHardware.new(),
       tick_count: 0
     )}
  end

  @impl true
  def handle_info(:tick, socket) do
    schedule_tick()

    %{machine: machine, sim: sim} = socket.assigns

    reading = SimulatedHardware.to_sensor_reading(sim)
    {cmd, machine} = CoffeeMaker.tick(machine, reading)
    sim = SimulatedHardware.tick(sim, cmd)

    {:noreply,
     assign(socket,
       machine: machine,
       sim: sim,
       tick_count: socket.assigns.tick_count + 1
     )}
  end

  # ---------------------------------------------------------------------------
  # User events — each maps to a single SimulatedHardware action
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("brew", _params, socket) do
    {:noreply, update(socket, :sim, &SimulatedHardware.press_button/1)}
  end

  def handle_event("remove_pot", _params, socket) do
    {:noreply, update(socket, :sim, &SimulatedHardware.remove_pot/1)}
  end

  def handle_event("place_pot", _params, socket) do
    {:noreply, update(socket, :sim, &SimulatedHardware.place_pot_empty/1)}
  end

  def handle_event("refill", _params, socket) do
    {:noreply, update(socket, :sim, &SimulatedHardware.refill_water/1)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="text-center">
        <h1 class="text-2xl font-bold text-zinc-900">Mark IV Special Coffee Maker</h1>
        <p class="text-sm text-zinc-500 mt-1">ALA LiveView Demo — zero-coupled domain logic</p>
      </div>

      <.machine_state_card machine={@machine} sim={@sim} />
      <.water_level_card sim={@sim} />
      <.pot_card sim={@sim} />
      <.hardware_card sim={@sim} />
      <.controls machine={@machine} sim={@sim} />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # UI Components — pure functions of assigns, no domain logic
  # ---------------------------------------------------------------------------

  defp machine_state_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 p-5">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-sm font-medium text-zinc-500 uppercase tracking-wide">Machine State</h2>
          <p class={"mt-1 text-xl font-semibold #{state_color(@machine.state)}"}>
            <%= state_label(@machine.state) %>
          </p>
        </div>
        <div class="flex items-center gap-3">
          <div class="text-right">
            <p class="text-xs text-zinc-400 uppercase">Indicator</p>
            <p class={"text-sm font-medium #{if indicator_on?(@sim), do: "text-amber-500", else: "text-zinc-300"}"}>
              <%= if indicator_on?(@sim), do: "ON", else: "OFF" %>
            </p>
          </div>
          <div class={[
            "w-4 h-4 rounded-full",
            if(indicator_on?(@sim), do: "bg-amber-400 shadow-lg shadow-amber-400/50", else: "bg-zinc-200")
          ]} />
        </div>
      </div>
    </div>
    """
  end

  defp water_level_card(assigns) do
    full = SimulatedHardware.full_level()
    pct = round(assigns.sim.water_level / full * 100)
    assigns = assign(assigns, pct: pct)

    ~H"""
    <div class="rounded-lg border border-zinc-200 p-5">
      <div class="flex items-center justify-between mb-2">
        <h2 class="text-sm font-medium text-zinc-500 uppercase tracking-wide">Water Reservoir</h2>
        <span class="text-sm font-mono text-zinc-600"><%= @pct %>%</span>
      </div>
      <div class="w-full bg-zinc-100 rounded-full h-3 overflow-hidden">
        <div
          class={[
            "h-3 rounded-full transition-all duration-500",
            water_bar_color(@pct)
          ]}
          style={"width: #{@pct}%"}
        />
      </div>
    </div>
    """
  end

  defp pot_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 p-5">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-sm font-medium text-zinc-500 uppercase tracking-wide">Warmer Plate</h2>
          <p class={"mt-1 text-lg font-medium #{pot_color(@sim.pot)}"}>
            <%= pot_label(@sim.pot) %>
          </p>
        </div>
        <div class="text-right">
          <p class="text-xs text-zinc-400 uppercase">Heater</p>
          <p class={"text-sm font-medium #{if warmer_on?(@sim), do: "text-orange-500", else: "text-zinc-300"}"}>
            <%= if warmer_on?(@sim), do: "ON", else: "OFF" %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp hardware_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 p-5">
      <h2 class="text-sm font-medium text-zinc-500 uppercase tracking-wide mb-3">Hardware Commands</h2>
      <div class="grid grid-cols-2 gap-3">
        <.hw_field label="Boiler Heater" value={cmd_val(@sim, :boiler_heater)} on="on" />
        <.hw_field label="Relief Valve" value={cmd_val(@sim, :relief_valve)} on="open" />
        <.hw_field label="Warmer Heater" value={cmd_val(@sim, :warmer_heater)} on="on" />
        <.hw_field label="Indicator" value={cmd_val(@sim, :indicator)} on="on" />
      </div>
    </div>
    """
  end

  defp hw_field(assigns) do
    active = to_string(assigns.value) == assigns.on

    assigns = assign(assigns, active: active)

    ~H"""
    <div class="flex items-center justify-between bg-zinc-50 rounded px-3 py-2">
      <span class="text-xs text-zinc-500"><%= @label %></span>
      <span class={"text-xs font-mono font-medium #{if @active, do: "text-emerald-600", else: "text-zinc-400"}"}>
        <%= String.upcase(to_string(@value)) %>
      </span>
    </div>
    """
  end

  defp controls(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 p-5">
      <h2 class="text-sm font-medium text-zinc-500 uppercase tracking-wide mb-3">Controls</h2>
      <div class="grid grid-cols-2 gap-3">
        <button
          phx-click="brew"
          disabled={@machine.state != :idle or @sim.pot == :removed or @sim.water_level == 0}
          class="rounded-lg px-4 py-2.5 text-sm font-semibold text-white bg-emerald-600 hover:bg-emerald-700 disabled:bg-zinc-200 disabled:text-zinc-400 disabled:cursor-not-allowed transition-colors"
        >
          Brew Coffee
        </button>
        <button
          phx-click="remove_pot"
          disabled={@sim.pot == :removed}
          class="rounded-lg px-4 py-2.5 text-sm font-semibold text-zinc-700 bg-zinc-100 hover:bg-zinc-200 disabled:text-zinc-300 disabled:cursor-not-allowed transition-colors"
        >
          Remove Pot
        </button>
        <button
          phx-click="place_pot"
          disabled={@sim.pot != :removed}
          class="rounded-lg px-4 py-2.5 text-sm font-semibold text-zinc-700 bg-zinc-100 hover:bg-zinc-200 disabled:text-zinc-300 disabled:cursor-not-allowed transition-colors"
        >
          Place Empty Pot
        </button>
        <button
          phx-click="refill"
          disabled={@sim.water_level == SimulatedHardware.full_level()}
          class="rounded-lg px-4 py-2.5 text-sm font-semibold text-blue-700 bg-blue-50 hover:bg-blue-100 disabled:bg-zinc-100 disabled:text-zinc-300 disabled:cursor-not-allowed transition-colors"
        >
          Refill Water
        </button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # View helpers — pure functions mapping domain values to display strings
  # ---------------------------------------------------------------------------

  defp state_label(:idle), do: "Idle"
  defp state_label(:brewing), do: "Brewing..."
  defp state_label(:brewed), do: "Coffee Ready"

  defp state_color(:idle), do: "text-zinc-600"
  defp state_color(:brewing), do: "text-emerald-600"
  defp state_color(:brewed), do: "text-amber-600"

  defp pot_label(:removed), do: "No pot"
  defp pot_label(:on_plate_empty), do: "Empty pot on plate"
  defp pot_label(:on_plate_with_coffee), do: "Pot with coffee"

  defp pot_color(:removed), do: "text-zinc-400"
  defp pot_color(:on_plate_empty), do: "text-zinc-600"
  defp pot_color(:on_plate_with_coffee), do: "text-amber-700"

  defp water_bar_color(pct) when pct > 50, do: "bg-blue-500"
  defp water_bar_color(pct) when pct > 20, do: "bg-yellow-500"
  defp water_bar_color(_pct), do: "bg-red-500"

  defp indicator_on?(%{last_cmd: %{indicator: :on}}), do: true
  defp indicator_on?(_sim), do: false

  defp warmer_on?(%{last_cmd: %{indicator: _} = cmd}), do: cmd.warmer_heater == :on
  defp warmer_on?(_sim), do: false

  defp cmd_val(%{last_cmd: nil}, _field), do: "-"
  defp cmd_val(%{last_cmd: cmd}, field), do: Map.get(cmd, field)

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)
end
