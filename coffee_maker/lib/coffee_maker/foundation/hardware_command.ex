defmodule CoffeeMaker.Foundation.HardwareCommand do
  @moduledoc """
  Foundation layer: all hardware outputs as a single pure value.

  In pass 1, each domain abstraction wrote to hardware directly during
  `poll_outputs/2`. Here, all output commands are gathered into this
  struct first, then written to hardware in one pass at the end of the
  cycle. Domain abstractions produce command values; nothing is written
  until the application layer assembles this struct and calls a driver.
  """

  @type on_off :: :on | :off
  @type open_closed :: :open | :closed

  @type t :: %__MODULE__{
          boiler_heater: on_off(),
          warmer_heater: on_off(),
          relief_valve: open_closed(),
          indicator: on_off()
        }

  @enforce_keys [:boiler_heater, :warmer_heater, :relief_valve, :indicator]
  defstruct [:boiler_heater, :warmer_heater, :relief_valve, :indicator]

  @doc "Write all commands to a live hardware module implementing HardwareApi."
  @spec write_to(t(), module()) :: :ok
  def write_to(cmd, hw) do
    hw.set_boiler_state(cmd.boiler_heater)
    hw.set_warmer_state(cmd.warmer_heater)
    hw.set_relief_valve(cmd.relief_valve)
    hw.set_indicator_state(cmd.indicator)
    :ok
  end
end
