defmodule ZeroCoupledWeb.Paradigms.BinderTest do
  use ExUnit.Case, async: true
  alias ZeroCoupledWeb.Paradigms.Binder

  defmodule Counter do
    defstruct n: 0
    def ports, do: %{in: [bump: :count], out: [count: :count, big: :flag]}
    def bump(%{n: n} = c, by), do: {%{c | n: n + by}, [count: n + by, big: n + by > 2]}
  end

  defmodule Flag do
    defstruct on: false
    def ports, do: %{in: [set: :flag], out: [on: :flag]}
    def set(f, on), do: {%{f | on: on}, [on: on]}
  end

  defmodule Tally do
    def parts, do: %{counter: Counter, flag: Flag}
    def ports, do: %{in: [bump: :count], out: [total: :count]}
    def streams, do: []
    def events, do: []
  end

  defmodule Page do
    def parts, do: %{}
    def ports, do: %{in: [], out: [mounted: :event]}
  end

  # partial maps on purpose: these test delivery, so they skip mount's soundness check
  defp socket(tally_bindings, page_bindings \\ %{}) do
    tally = Binder.story(Tally, %{counter: %Counter{}, flag: %Flag{}}, tally_bindings)
    page = Binder.story(Page, %{}, page_bindings)
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}, page: page, tally: tally}}
  end

  test "mount refuses an unsound composition" do
    tally = Binder.story(Tally, %{counter: %Counter{}, flag: %Flag{}}, %{})

    assert_raise ArgumentError, ~r/unsound composition/, fn ->
      Binder.mount(%Phoenix.LiveView.Socket{}, {Binder.story(Page, %{}, %{}), %{tally: tally}})
    end
  end

  test "outputs land where the story's map says, including on another part's input and out of the story" do
    s =
      socket(
        %{
          {:in, :bump} => [{:input, :counter, &Counter.bump/2}],
          {:counter, :count} => [{:show, :count}, {:out, :total}],
          {:counter, :big} => [{:input, :flag, &Flag.set/2}],
          {:flag, :on} => [{:set, :flag_on, true}, {:flash_for, :info, %{true => "big now"}}]
        },
        %{{:tally, :total} => [{:show, :page_total}]}
      )
      |> Binder.input(:tally, :bump, 3)

    assert %{count: 3, flag_on: true} = s.assigns.tally.view
    assert %{counter: %Counter{n: 3}, flag: %Flag{on: true}} = s.assigns.tally.parts
    assert s.assigns.page_total == 3
    assert s.assigns.flash == %{"info" => "big now"}
  end

  test "a timer reports to the story's own input after the delay, and can be stopped" do
    s =
      socket(%{
        {:counter, :count} => [{:start_timer, :tick, 10, :bump}],
        {:counter, :big} => [{:stop_timer, :tick}]
      })

    s = Binder.deliver(s, :tally, {:counter, :count}, 1)
    assert_receive {:story_input, :tally, :bump, 1}, 100
    s = Binder.deliver(s, :tally, {:counter, :count}, 6)
    _ = Binder.deliver(s, :tally, {:counter, :big}, true)
    refute_receive {:story_input, :tally, :bump, 6}, 50
  end

  defmodule EchoGateway do
    def create_checkout_session(items, meta, urls), do: {:ok, {items, meta, urls}}
  end

  test "a via binding asks a configured Call instance; a task's outcome reaches the input named for it" do
    pay = %ZeroCoupled.Domain.StartPayment{gateway: EchoGateway, urls: :urls, cart_key: "cart"}

    s =
      socket(%{{:in, :bump} => [{:via, pay, [{:show, :asked}]}]})
      |> Binder.input(:tally, :bump, {[:line], 7})

    assert s.assigns.tally.view.asked == {:ok, {[:line], %{"cart" => 7}, :urls}}

    s =
      socket(%{
        {:in, :bump} => [{:input, :counter, &Counter.bump/2}],
        {:counter, :count} => [{:show, :count}]
      })

    s = Binder.async_result(s, {:story_async, :tally, :bump, :bump}, {:ok, {:ok, 4}})
    assert s.assigns.tally.view.count == 4
  end
end
