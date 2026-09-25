defmodule CoffeeMaker.DomainAbstractions.Boiler do
  @moduledoc """
  Domain abstraction: a boiler that heats water.

  Knows nothing about coffee machines, UIs, or warmer plates. Depends
  only on the Foundation layer's SensorReading type.

  ## Signals (live dataflow ports)

    - `empty`                    — output — true when no water remains
    - `on`                       — input  — the application requests heating
    - `open_steam_release_valve` — input  — the application requests valve open

  ## Safety logic (internal)

  The boiler enforces its own invariant: the heater is off whenever the
  boiler is empty or the valve is open. This logic lives here, not in the
  application, because it belongs to the boiler abstraction.

  ## Usage

      boiler = Boiler.read(reading)
      # ... application logic sets boiler.on and boiler.open_steam_release_valve ...
      heater_cmd = Boiler.heater_cmd(boiler)  # :on | :off
      valve_cmd  = Boiler.valve_cmd(boiler)   # :open | :closed
  """

  alias CoffeeMaker.Foundation.SensorReading

  @type t :: %__MODULE__{on: boolean(), empty: boolean(), open_steam_release_valve: boolean()}

  defstruct on: false, empty: false, open_steam_release_valve: false

  @doc "Extract signals from a SensorReading."
  @spec read(SensorReading.t()) :: t()
  def read(%SensorReading{boiler_status: status}) do
    %__MODULE__{empty: status == :empty}
  end

  @doc "Produce the boiler-heater hardware command, enforcing safety."
  @spec heater_cmd(t()) :: :on | :off
  def heater_cmd(%__MODULE__{on: on, empty: empty, open_steam_release_valve: open}) do
    if on and not empty and not open, do: :on, else: :off
  end

  @doc "Produce the steam-relief-valve hardware command."
  @spec valve_cmd(t()) :: :open | :closed
  def valve_cmd(%__MODULE__{open_steam_release_valve: open}) do
    if open, do: :open, else: :closed
  end
end
