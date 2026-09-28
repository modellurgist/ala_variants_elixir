defmodule ZeroCoupledWeb.Paradigms.BinderTest do
  use ExUnit.Case, async: true
  alias ZeroCoupledWeb.Paradigms.Binder

  defmodule Counter do
    defstruct n: 0
    def bump(%{n: n} = c, by), do: {%{c | n: n + by}, [count: n + by, big: n + by > 2]}
  end

  defmodule Flag do
    defstruct on: false
    def set(f, on), do: {%{f | on: on}, [on: on]}
  end

  defp socket,
    do: %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}, counter: %Counter{}, flag: %Flag{}}
    }

  test "outputs land where the bindings say, including on another feature's input" do
    bindings = %{
      {:counter, :count} => [{:assign, :count}, {:set, :touched, true}],
      {:counter, :big} => [{:input, :flag, &Flag.set/2}],
      {:flag, :on} => [{:assign, :flag_on}, {:flash_for, :info, %{true => "big now"}}]
    }

    s = Binder.run(socket(), bindings, :counter, &Counter.bump(&1, 3))

    assert %{
             count: 3,
             touched: true,
             flag_on: true,
             counter: %Counter{n: 3},
             flag: %Flag{on: true}
           } = s.assigns

    assert s.assigns.flash == %{"info" => "big now"}
  end

  test "an unbound port is dropped; a via binding transforms before delivering" do
    bindings = %{{:counter, :count} => [{:via, &(&1 * 10), [{:assign, :tens}]}]}
    s = Binder.run(socket(), bindings, :counter, &Counter.bump(&1, 1))
    assert s.assigns.tens == 10
    refute Map.has_key?(s.assigns, :count)
  end

  test "a timer binding sends to self after the delay and can be cancelled" do
    bindings = %{{:counter, :count} => [{:timer, :tick, 10}]}
    s = Binder.deliver(socket(), bindings, :counter, count: {:start, :payload})
    assert_receive {:timer, :tick, :payload}, 100
    s = Binder.deliver(s, bindings, :counter, count: {:start, :again})
    _ = Binder.deliver(s, bindings, :counter, count: :cancel)
    refute_receive {:timer, :tick, :again}, 50
  end
end
