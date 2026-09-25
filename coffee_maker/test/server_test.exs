defmodule CoffeeMaker.ServerTest do
  use ExUnit.Case, async: true

  alias CoffeeMaker.Server

  # A minimal @behaviour-based stub. No Mox needed — just a module that
  # satisfies the HardwareApi contract. This is the ALA pattern: the
  # Foundation layer's @callback behaviour enables substitution at the
  # boundary without any framework.
  defmodule IdleHardware do
    @behaviour CoffeeMaker.Foundation.HardwareApi

    @impl true
    def get_brew_button_status, do: :not_pushed
    @impl true
    def get_boiler_status, do: :not_empty
    @impl true
    def get_warmer_plate_status, do: :pot_not_empty
    @impl true
    def set_boiler_state(_), do: :ok
    @impl true
    def set_warmer_state(_), do: :ok
    @impl true
    def set_indicator_state(_), do: :ok
    @impl true
    def set_relief_valve(_), do: :ok
  end

  describe "lifecycle" do
    test "starts, polls, and reports state" do
      {:ok, pid} = Server.start_link(hw: IdleHardware, interval_ms: 10)
      Process.sleep(50)
      assert Server.state(pid).state == :idle
      :ok = Server.stop(pid)
    end

    test "stops gracefully with :normal reason" do
      {:ok, pid} = Server.start_link(hw: IdleHardware, interval_ms: 10)
      ref = Process.monitor(pid)
      :ok = Server.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "accepts :name option for registration" do
      name = :"server_test_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Server.start_link(hw: IdleHardware, interval_ms: 10, name: name)
      assert Server.state(name).state == :idle
      Server.stop(name)
    end
  end

  describe "supervision" do
    test "works under a Supervisor" do
      name = :"supervised_test_#{System.unique_integer([:positive])}"

      children = [
        {Server, hw: IdleHardware, interval_ms: 10, name: name}
      ]

      {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

      Process.sleep(30)
      assert Server.state(name).state == :idle

      Supervisor.stop(sup)
    end
  end
end
