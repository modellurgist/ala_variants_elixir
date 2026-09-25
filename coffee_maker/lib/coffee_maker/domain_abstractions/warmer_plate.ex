defmodule CoffeeMaker.DomainAbstractions.WarmerPlate do
  @moduledoc """
  Domain abstraction: a heated plate that keeps a coffee pot warm.

  Knows nothing about coffee machines, UIs, or boilers. Depends only
  on the Foundation layer's SensorReading type.

  ## Signals (live dataflow ports)

    - `pot_on_plate` — output — true when a container is on the plate
    - `pot_empty`    — output — true when the container is empty

  ## Self-contained heater logic

  The warmer plate controls its own heater: it heats only when a
  non-empty pot is present. This logic lives here, not in the
  application.

  ## Usage

      warmer = WarmerPlate.read(reading)
      heater_cmd = WarmerPlate.heater_cmd(warmer)  # :on | :off
  """

  alias CoffeeMaker.Foundation.SensorReading

  @type t :: %__MODULE__{pot_on_plate: boolean(), pot_empty: boolean()}

  defstruct pot_on_plate: false, pot_empty: false

  @doc "Extract signals from a SensorReading."
  @spec read(SensorReading.t()) :: t()
  def read(%SensorReading{warmer_plate_status: status}) do
    %__MODULE__{
      pot_on_plate: status != :warmer_empty,
      pot_empty: status == :pot_empty
    }
  end

  @doc "Produce the warmer-heater hardware command."
  @spec heater_cmd(t()) :: :on | :off
  def heater_cmd(%__MODULE__{pot_on_plate: on_plate, pot_empty: empty}) do
    if on_plate and not empty, do: :on, else: :off
  end
end
