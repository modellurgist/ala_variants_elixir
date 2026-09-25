defmodule CoffeeMaker.Foundation.SimulatedHardware do
  @moduledoc """
  Foundation layer: in-memory simulation of the coffee machine's physical state.

  Models the physical world that the real `HardwareApi` would read from and
  write to. The simulation produces `SensorReading` structs and consumes
  `HardwareCommand` structs — the same pure data boundary that the real
  hardware driver uses.

  This module knows nothing about `CoffeeMaker`, user interfaces, or
  LiveView. It is a Foundation-layer abstraction: a substitute for the
  physical hardware, not for the machine logic.

  ## Physical model

    - Water reservoir holds `@full_level` ticks of water.
    - While the boiler heater command is `:on`, one tick of water drains
      per simulation step.
    - When the reservoir empties, the pot transitions from empty to
      containing coffee.
    - The brew button is momentary — it auto-clears after one tick.

  ## Usage

      sim = SimulatedHardware.new()
      reading = SimulatedHardware.to_sensor_reading(sim)
      # ... push reading through CoffeeMaker, get cmd back ...
      sim = SimulatedHardware.tick(sim, cmd)
  """

  alias CoffeeMaker.Foundation.{HardwareCommand, SensorReading}

  @full_level 20

  @type pot_state :: :removed | :on_plate_empty | :on_plate_with_coffee

  @type t :: %__MODULE__{
          water_level: non_neg_integer(),
          pot: pot_state(),
          button_pressed: boolean(),
          last_cmd: HardwareCommand.t() | nil
        }

  defstruct water_level: @full_level,
            pot: :on_plate_empty,
            button_pressed: false,
            last_cmd: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []), do: struct!(__MODULE__, opts)

  @spec full_level() :: pos_integer()
  def full_level, do: @full_level

  # ---------------------------------------------------------------------------
  # Sensor reading — what the CoffeeMaker sees
  # ---------------------------------------------------------------------------

  @spec to_sensor_reading(t()) :: SensorReading.t()
  def to_sensor_reading(%__MODULE__{} = sim) do
    SensorReading.new(
      button_status: if(sim.button_pressed, do: :pushed, else: :not_pushed),
      boiler_status: if(sim.water_level > 0, do: :not_empty, else: :empty),
      warmer_plate_status:
        case sim.pot do
          :removed -> :warmer_empty
          :on_plate_empty -> :pot_empty
          :on_plate_with_coffee -> :pot_not_empty
        end
    )
  end

  # ---------------------------------------------------------------------------
  # Simulation step — advance physical state by one tick
  # ---------------------------------------------------------------------------

  @spec tick(t(), HardwareCommand.t()) :: t()
  def tick(%__MODULE__{} = sim, %HardwareCommand{} = cmd) do
    sim
    |> store_command(cmd)
    |> drain_water(cmd)
    |> clear_button()
  end

  defp store_command(sim, cmd), do: %{sim | last_cmd: cmd}

  defp drain_water(sim, cmd) do
    if cmd.boiler_heater == :on and sim.water_level > 0 do
      new_level = sim.water_level - 1
      sim = %{sim | water_level: new_level}

      if new_level == 0 and sim.pot == :on_plate_empty do
        %{sim | pot: :on_plate_with_coffee}
      else
        sim
      end
    else
      sim
    end
  end

  defp clear_button(sim), do: %{sim | button_pressed: false}

  # ---------------------------------------------------------------------------
  # User actions — the physical things a person does to the machine
  # ---------------------------------------------------------------------------

  @spec press_button(t()) :: t()
  def press_button(%__MODULE__{} = sim), do: %{sim | button_pressed: true}

  @spec remove_pot(t()) :: t()
  def remove_pot(%__MODULE__{} = sim), do: %{sim | pot: :removed}

  @spec place_pot_empty(t()) :: t()
  def place_pot_empty(%__MODULE__{} = sim), do: %{sim | pot: :on_plate_empty}

  @spec refill_water(t()) :: t()
  def refill_water(%__MODULE__{} = sim), do: %{sim | water_level: @full_level}
end
