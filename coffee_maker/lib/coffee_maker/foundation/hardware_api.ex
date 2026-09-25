defmodule CoffeeMaker.Foundation.HardwareApi do
  @moduledoc """
  Foundation layer: contract for the physical hardware driver.

  This behaviour is implemented once for production hardware and once by
  any integration-test mock (Mox). Unit tests for the machine logic do
  not need it at all — they work directly with SensorReading and
  HardwareCommand structs.

  This is the same granular interface as pass 1. The difference is that
  domain abstractions no longer receive or call a `hw` module. Only two
  thin functions at the application boundary (`SensorReading.from_hardware/1`
  and `HardwareCommand.write_to/2`) depend on this behaviour.
  """

  @type warmer_plate_status :: :warmer_empty | :pot_empty | :pot_not_empty
  @type boiler_status :: :empty | :not_empty
  @type brew_button_status :: :pushed | :not_pushed
  @type on_off :: :on | :off
  @type open_closed :: :open | :closed

  @callback get_warmer_plate_status() :: warmer_plate_status()
  @callback get_boiler_status() :: boiler_status()
  @callback get_brew_button_status() :: brew_button_status()
  @callback set_boiler_state(on_off()) :: :ok
  @callback set_warmer_state(on_off()) :: :ok
  @callback set_indicator_state(on_off()) :: :ok
  @callback set_relief_valve(open_closed()) :: :ok
end
