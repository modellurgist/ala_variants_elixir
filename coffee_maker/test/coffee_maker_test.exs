defmodule CoffeeMakerTest do
  use ExUnit.Case, async: true

  alias CoffeeMaker.Foundation.{HardwareCommand, SensorReading}
  alias CoffeeMaker.Compose.{Chain, Step}

  # ---------------------------------------------------------------------------
  # Helpers — build SensorReadings with atom shorthand
  # ---------------------------------------------------------------------------

  defp reading(overrides \\ []) do
    defaults = [
      button_status: :not_pushed,
      boiler_status: :not_empty,
      warmer_plate_status: :pot_not_empty
    ]

    SensorReading.new(Keyword.merge(defaults, overrides))
  end

  defp push(machine, overrides \\ []) do
    {:emit, cmd, machine} = Step.push(machine, reading(overrides))
    {cmd, machine}
  end

  # ---------------------------------------------------------------------------
  # Initial state
  # ---------------------------------------------------------------------------

  describe "initial state" do
    test "starts idle" do
      assert CoffeeMaker.new().state == :idle
    end
  end

  # ---------------------------------------------------------------------------
  # User Story 1: button press starts brewing
  # ---------------------------------------------------------------------------

  describe "brew button pressed (pot on plate, water available)" do
    test "transitions to brewing" do
      {_cmd, machine} = push(CoffeeMaker.new(), button_status: :pushed)
      assert machine.state == :brewing
    end

    test "does NOT brew when boiler is empty" do
      {_cmd, machine} = push(CoffeeMaker.new(), button_status: :pushed, boiler_status: :empty)
      assert machine.state == :idle
    end

    test "does NOT brew when no pot on plate" do
      {_cmd, machine} = push(CoffeeMaker.new(), button_status: :pushed, warmer_plate_status: :warmer_empty)
      assert machine.state == :idle
    end
  end

  # ---------------------------------------------------------------------------
  # User Story 2: boiler heater is on while brewing
  # ---------------------------------------------------------------------------

  describe "boiler heater" do
    test "turns on when brewing starts" do
      {cmd, _} = push(CoffeeMaker.new(), button_status: :pushed)
      assert cmd.boiler_heater == :on
    end

    test "stays off when idle" do
      {cmd, _} = push(CoffeeMaker.new())
      assert cmd.boiler_heater == :off
    end
  end

  # ---------------------------------------------------------------------------
  # User Story 3: pot removal opens relief valve
  # ---------------------------------------------------------------------------

  describe "steam relief valve" do
    test "opens when pot is off the plate" do
      {cmd, _} = push(CoffeeMaker.new(), warmer_plate_status: :warmer_empty)
      assert cmd.relief_valve == :open
    end

    test "stays closed when pot is on plate" do
      {cmd, _} = push(CoffeeMaker.new(), warmer_plate_status: :pot_not_empty)
      assert cmd.relief_valve == :closed
    end
  end

  # ---------------------------------------------------------------------------
  # User Story 4: boiler empty → brewed, indicator on
  # ---------------------------------------------------------------------------

  describe "boiler runs dry" do
    test "transitions from brewing to brewed" do
      machine = CoffeeMaker.new()
      {_cmd, machine} = push(machine, button_status: :pushed)
      assert machine.state == :brewing

      {cmd, machine} = push(machine, boiler_status: :empty)
      assert machine.state == :brewed
      assert cmd.indicator == :on
    end

    test "indicator light is off when idle" do
      {cmd, _} = push(CoffeeMaker.new())
      assert cmd.indicator == :off
    end
  end

  # ---------------------------------------------------------------------------
  # User Story 5: empty pot replaced → back to idle
  # ---------------------------------------------------------------------------

  describe "pot replaced" do
    test "returns to idle when empty pot is placed" do
      machine = CoffeeMaker.new()
      {_, machine} = push(machine, button_status: :pushed)
      {_, machine} = push(machine, boiler_status: :empty)
      assert machine.state == :brewed

      {_, machine} = push(machine, boiler_status: :empty)
      assert machine.state == :brewed

      {_, machine} = push(machine, boiler_status: :empty, warmer_plate_status: :pot_empty)
      assert machine.state == :idle
    end
  end

  # ---------------------------------------------------------------------------
  # Boiler safety: heater off when valve open (even during brewing)
  # ---------------------------------------------------------------------------

  describe "boiler safety" do
    test "heater is off when pot is removed during brewing (valve open overrides)" do
      machine = CoffeeMaker.new()
      {cmd, machine} = push(machine, button_status: :pushed)
      assert machine.state == :brewing
      assert cmd.boiler_heater == :on

      {cmd, _machine} = push(machine, warmer_plate_status: :warmer_empty)
      assert cmd.relief_valve == :open
      assert cmd.boiler_heater == :off
    end
  end

  # ---------------------------------------------------------------------------
  # Warmer plate heater (internal self-management)
  # ---------------------------------------------------------------------------

  describe "warmer plate heater" do
    test "heats when a non-empty pot is on the plate" do
      {cmd, _} = push(CoffeeMaker.new(), warmer_plate_status: :pot_not_empty)
      assert cmd.warmer_heater == :on
    end

    test "does not heat when pot is empty" do
      {cmd, _} = push(CoffeeMaker.new(), warmer_plate_status: :pot_empty)
      assert cmd.warmer_heater == :off
    end

    test "does not heat when no pot" do
      {cmd, _} = push(CoffeeMaker.new(), warmer_plate_status: :warmer_empty)
      assert cmd.warmer_heater == :off
    end
  end

  # ---------------------------------------------------------------------------
  # Full lifecycle
  # ---------------------------------------------------------------------------

  describe "complete coffee cycle" do
    test "idle → brewing → brewed → idle" do
      machine = CoffeeMaker.new()

      {_, machine} = push(machine)
      assert machine.state == :idle

      {_, machine} = push(machine, button_status: :pushed)
      assert machine.state == :brewing

      {_, machine} = push(machine)
      assert machine.state == :brewing

      {cmd, machine} = push(machine, boiler_status: :empty)
      assert machine.state == :brewed
      assert cmd.indicator == :on

      {cmd, machine} = push(machine, boiler_status: :empty, warmer_plate_status: :pot_empty)
      assert machine.state == :idle
      assert cmd.indicator == :off
    end
  end

  # ---------------------------------------------------------------------------
  # Chain integration — drive with a list of readings
  # ---------------------------------------------------------------------------

  describe "Chain.fold integration" do
    test "can drive the machine with a list of SensorReadings" do
      readings = [
        reading(),
        reading(button_status: :pushed),
        reading(),
        reading(boiler_status: :empty),
        reading(boiler_status: :empty, warmer_plate_status: :pot_empty)
      ]

      {cmds, machine} = Chain.fold(CoffeeMaker.new(), readings)

      assert length(cmds) == 5
      assert Enum.at(cmds, 0).boiler_heater == :off
      assert Enum.at(cmds, 1).boiler_heater == :on
      assert Enum.at(cmds, 3).indicator == :on
      assert Enum.at(cmds, 4).indicator == :off
      assert machine.state == :idle
    end

    test "command history is a plain list — no processes, no async" do
      readings = List.duplicate(reading(), 10)
      {cmds, _} = Chain.fold(CoffeeMaker.new(), readings)
      assert Enum.all?(cmds, &match?(%HardwareCommand{}, &1))
    end
  end
end
