defmodule CoffeeMaker.Foundation.SensorReading do
  @moduledoc """
  Foundation layer: all hardware inputs as a single pure value.

  In pass 1, domain abstractions each called the hardware API directly
  (`hw.get_boiler_status()`, etc.). Here, all sensor reads are gathered
  *once* per cycle into this struct. Domain abstractions never touch
  the hardware module — they only pattern-match on a SensorReading.

  This separation means the machine's logic can be tested by constructing
  a SensorReading directly. No mocking required.
  """

  @type button_status :: :pushed | :not_pushed
  @type boiler_status :: :empty | :not_empty
  @type warmer_plate_status :: :warmer_empty | :pot_empty | :pot_not_empty

  @type t :: %__MODULE__{
          button_status: button_status(),
          boiler_status: boiler_status(),
          warmer_plate_status: warmer_plate_status()
        }

  @enforce_keys [:button_status, :boiler_status, :warmer_plate_status]
  defstruct [:button_status, :boiler_status, :warmer_plate_status]

  @doc "Convenience constructor with keyword args."
  @spec new(keyword()) :: t()
  def new(opts), do: struct!(__MODULE__, opts)

  @doc "Read from a live hardware module implementing HardwareApi."
  @spec from_hardware(module()) :: t()
  def from_hardware(hw) do
    %__MODULE__{
      button_status: hw.get_brew_button_status(),
      boiler_status: hw.get_boiler_status(),
      warmer_plate_status: hw.get_warmer_plate_status()
    }
  end
end
