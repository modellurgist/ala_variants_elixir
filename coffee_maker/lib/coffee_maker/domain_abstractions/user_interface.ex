defmodule CoffeeMaker.DomainAbstractions.UserInterface do
  @moduledoc """
  Domain abstraction: a push-button and an indicator lamp.

  Knows nothing about coffee, boilers, or warmer plates. Depends only on
  the Foundation layer's SensorReading type.

  ## Signals (live dataflow ports)

    - `button`   — output — true when the user has pressed the brew button
    - `light_on` — input  — the application sets this to request the lamp on

  ## Usage

      ui = UserInterface.read(reading)
      # ... application logic sets ui.light_on ...
      cmd_value = UserInterface.indicator_cmd(ui)  # :on | :off
  """

  alias CoffeeMaker.Foundation.SensorReading

  @type t :: %__MODULE__{button: boolean(), light_on: boolean()}

  defstruct button: false, light_on: false

  @doc "Extract signals from a SensorReading."
  @spec read(SensorReading.t()) :: t()
  def read(%SensorReading{button_status: status}) do
    %__MODULE__{button: status == :pushed}
  end

  @doc "Produce the indicator-lamp hardware command."
  @spec indicator_cmd(t()) :: :on | :off
  def indicator_cmd(%__MODULE__{light_on: on}), do: if(on, do: :on, else: :off)
end
