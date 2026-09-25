defmodule CoffeeMaker.Foundation.SimulatedHardwareTest do
  use ExUnit.Case, async: true

  alias CoffeeMaker.Foundation.{HardwareCommand, SimulatedHardware}
  alias CoffeeMaker.Compose.Step

  defp idle_cmd do
    %HardwareCommand{boiler_heater: :off, warmer_heater: :off, relief_valve: :closed, indicator: :off}
  end

  defp brewing_cmd do
    %HardwareCommand{boiler_heater: :on, warmer_heater: :off, relief_valve: :closed, indicator: :off}
  end

  describe "initial state" do
    test "starts with full water, empty pot on plate, button not pressed" do
      sim = SimulatedHardware.new()
      assert sim.water_level == SimulatedHardware.full_level()
      assert sim.pot == :on_plate_empty
      refute sim.button_pressed
    end

    test "initial sensor reading reflects idle hardware" do
      reading = SimulatedHardware.new() |> SimulatedHardware.to_sensor_reading()
      assert reading.button_status == :not_pushed
      assert reading.boiler_status == :not_empty
      assert reading.warmer_plate_status == :pot_empty
    end
  end

  describe "user actions" do
    test "press_button sets button_pressed" do
      sim = SimulatedHardware.new() |> SimulatedHardware.press_button()
      assert sim.button_pressed
      assert SimulatedHardware.to_sensor_reading(sim).button_status == :pushed
    end

    test "remove_pot changes warmer plate status" do
      sim = SimulatedHardware.new() |> SimulatedHardware.remove_pot()
      assert sim.pot == :removed
      assert SimulatedHardware.to_sensor_reading(sim).warmer_plate_status == :warmer_empty
    end

    test "place_pot_empty restores pot" do
      sim =
        SimulatedHardware.new()
        |> SimulatedHardware.remove_pot()
        |> SimulatedHardware.place_pot_empty()

      assert sim.pot == :on_plate_empty
      assert SimulatedHardware.to_sensor_reading(sim).warmer_plate_status == :pot_empty
    end

    test "refill_water restores full level" do
      sim = SimulatedHardware.new(water_level: 0) |> SimulatedHardware.refill_water()
      assert sim.water_level == SimulatedHardware.full_level()
    end
  end

  describe "tick/2 simulation physics" do
    test "water drains when boiler heater is on" do
      sim = SimulatedHardware.new()
      sim = SimulatedHardware.tick(sim, brewing_cmd())
      assert sim.water_level == SimulatedHardware.full_level() - 1
    end

    test "water does not drain when boiler heater is off" do
      sim = SimulatedHardware.new()
      sim = SimulatedHardware.tick(sim, idle_cmd())
      assert sim.water_level == SimulatedHardware.full_level()
    end

    test "button clears after one tick" do
      sim = SimulatedHardware.new() |> SimulatedHardware.press_button()
      assert sim.button_pressed
      sim = SimulatedHardware.tick(sim, idle_cmd())
      refute sim.button_pressed
    end

    test "pot gets coffee when water fully drains" do
      sim = SimulatedHardware.new(water_level: 1)
      sim = SimulatedHardware.tick(sim, brewing_cmd())
      assert sim.water_level == 0
      assert sim.pot == :on_plate_with_coffee
    end

    test "pot stays removed even when water drains" do
      sim = SimulatedHardware.new(water_level: 1) |> SimulatedHardware.remove_pot()
      sim = SimulatedHardware.tick(sim, brewing_cmd())
      assert sim.pot == :removed
    end

    test "stores the last command" do
      sim = SimulatedHardware.new()
      sim = SimulatedHardware.tick(sim, brewing_cmd())
      assert sim.last_cmd == brewing_cmd()
    end
  end

  describe "full brew cycle with CoffeeMaker" do
    test "complete lifecycle: idle -> brew -> brewed -> idle" do
      sim = SimulatedHardware.new()
      machine = CoffeeMaker.new()

      sim = SimulatedHardware.press_button(sim)

      {sim, machine, _cmds} = run_ticks(sim, machine, SimulatedHardware.full_level() + 5)

      assert machine.state == :brewed

      sim = SimulatedHardware.remove_pot(sim)
      {sim, machine, _cmds} = run_ticks(sim, machine, 2)

      sim = SimulatedHardware.place_pot_empty(sim)
      {_sim, machine, _cmds} = run_ticks(sim, machine, 2)

      assert machine.state == :idle
    end
  end

  defp run_ticks(sim, machine, n) do
    Enum.reduce(1..n, {sim, machine, []}, fn _i, {sim, machine, cmds} ->
      reading = SimulatedHardware.to_sensor_reading(sim)
      {:emit, cmd, machine} = Step.push(machine, reading)
      sim = SimulatedHardware.tick(sim, cmd)
      {sim, machine, [cmd | cmds]}
    end)
  end
end
