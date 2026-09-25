defmodule CoffeeMaker do
  @moduledoc """
  Application layer: The Mark IV Special coffee maker (pass-3 version).

  This module is the only place where the word "coffee" appears. It
  instantiates the three domain abstractions (UserInterface, Boiler,
  WarmerPlate), expresses the user stories as 6 lines of logic, and
  assembles hardware commands from the domain abstractions' outputs.

  ## What changed from pass 1

  The machine is now a **`Step`** — push a `SensorReading` in, get a
  `HardwareCommand` out. State (idle/brewing/brewed + edge-detection
  memory) lives in this struct.

  The hardware API is no longer threaded through every function call.
  Instead:
    - `SensorReading.from_hardware/1` reads all sensors at once (once
      per cycle, at the top boundary).
    - `HardwareCommand.write_to/2` writes all outputs at once (once per
      cycle, at the bottom boundary).
    - Domain abstractions work with pure data — they never call the
      hardware module.

  ## Benefits for testing

  Tests construct `SensorReading` structs and pattern-match on
  `HardwareCommand` structs. No Mox setup, no mock expectations, no
  process teardown.

  ## Running against real hardware

      # In a supervision tree (production)
      children = [{CoffeeMachineV3.Server, hw: MyHardwareDriver}]
      Supervisor.start_link(children, strategy: :one_for_one)

      # Quick script / IEx session
      CoffeeMaker.run_with(MyHardwareDriver)

  ## User stories (from the ALA diagram)

  1. Button + water + pot on plate → start brewing
  2. While brewing → boiler heater on
  3. Pot removed → relief valve opens (stops water flow)
  4. Boiler runs dry → brewing done, indicator light on
  5. Empty pot replaced → back to idle
  """

  alias CoffeeMaker.DomainAbstractions.{Boiler, UserInterface, WarmerPlate}
  alias CoffeeMaker.Foundation.{HardwareCommand, SensorReading}
  alias CoffeeMaker.Compose.Step

  @type machine_state :: :idle | :brewing | :brewed

  @type t :: %__MODULE__{
          state: machine_state(),
          prev_boiler_empty: boolean() | nil,
          prev_pot_empty: boolean() | nil
        }

  defstruct state: :idle,
            prev_boiler_empty: nil,
            prev_pot_empty: nil

  # ---------------------------------------------------------------------------
  # Step protocol — delegates to the module's own functions
  # ---------------------------------------------------------------------------

  defimpl Step do
    def push(machine, %SensorReading{} = reading) do
      CoffeeMaker.do_cycle(machine, reading)
    end
  end

  @doc """
  Run one processing cycle: read a `SensorReading`, apply machine logic,
  return the resulting `HardwareCommand` and updated machine state.

  This is the domain-named entry point — callers see "tick the coffee
  machine with a reading" rather than the generic `Step.push` protocol.
  """
  @spec tick(t(), SensorReading.t()) :: {HardwareCommand.t(), t()}
  def tick(%__MODULE__{} = machine, %SensorReading{} = reading) do
    {:emit, cmd, machine} = do_cycle(machine, reading)
    {cmd, machine}
  end

  @doc false
  @spec do_cycle(t(), SensorReading.t()) :: {:emit, HardwareCommand.t(), t()}
  def do_cycle(%__MODULE__{} = machine, %SensorReading{} = reading) do
    ui = UserInterface.read(reading)
    boiler = Boiler.read(reading)
    warmer = WarmerPlate.read(reading)

    {machine, ui, boiler, warmer} = apply_logic(machine, ui, boiler, warmer)

    cmd = %HardwareCommand{
      boiler_heater: Boiler.heater_cmd(boiler),
      relief_valve: Boiler.valve_cmd(boiler),
      warmer_heater: WarmerPlate.heater_cmd(warmer),
      indicator: UserInterface.indicator_cmd(ui)
    }

    {:emit, cmd, machine}
  end

  # ---------------------------------------------------------------------------
  # The 6 lines of application logic
  #
  # These correspond one-to-one with lines in the ALA coffee maker diagram:
  #
  #   1. if button && potOnPlate && !empty → state=Brewing; button=false
  #   2. valve = !potOnPlate
  #   3. boiler.on = (state == Brewing)
  #   4. if empty && !prevEmpty → state=Brewed
  #   5. if potEmpty && !prevPotEmpty → state=Idle
  #   6. light = (state == Brewed)
  # ---------------------------------------------------------------------------

  defp apply_logic(machine, ui, boiler, warmer) do
    # Line 1
    state =
      if ui.button and warmer.pot_on_plate and not boiler.empty,
        do: :brewing,
        else: machine.state

    ui = %{ui | button: false}

    # Line 2
    boiler = %{boiler | open_steam_release_valve: not warmer.pot_on_plate}

    # Line 3
    boiler = %{boiler | on: state == :brewing}

    # Line 4 (skip first poll — nil prev means no edge yet)
    state =
      if machine.prev_boiler_empty != nil and boiler.empty and not machine.prev_boiler_empty,
        do: :brewed,
        else: state

    # Line 5
    state =
      if machine.prev_pot_empty != nil and warmer.pot_empty and not machine.prev_pot_empty,
        do: :idle,
        else: state

    # Line 6
    ui = %{ui | light_on: state == :brewed}

    machine = %{machine |
      state: state,
      prev_boiler_empty: boiler.empty,
      prev_pot_empty: warmer.pot_empty
    }

    {machine, ui, boiler, warmer}
  end

  # ---------------------------------------------------------------------------
  # Convenience helpers
  # ---------------------------------------------------------------------------

  @doc "Create a fresh machine in the idle state."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Run one poll cycle against a live hardware module.

  Returns `{hardware_command, updated_machine}`.
  """
  @spec poll(t(), module()) :: {HardwareCommand.t(), t()}
  def poll(machine, hw) do
    reading = SensorReading.from_hardware(hw)
    {cmd, machine} = tick(machine, reading)
    HardwareCommand.write_to(cmd, hw)
    {cmd, machine}
  end

  @doc """
  Run a continuous polling loop against a live hardware module.

  Suitable for scripts and quick experiments. For production, use
  `CoffeeMaker.Server` which provides OTP supervision,
  graceful shutdown, and runtime state inspection.
  """
  @spec run_with(module(), pos_integer()) :: no_return()
  def run_with(hw, interval_ms \\ 100) do
    run_loop(hw, new(), interval_ms)
  end

  defp run_loop(hw, machine, interval_ms) do
    {_cmd, machine} = poll(machine, hw)
    Process.sleep(interval_ms)
    run_loop(hw, machine, interval_ms)
  end
end
