defmodule ZeroCoupled.GenFixtures do
  @moduledoc """
  A minimal two-feature page used to exercise
  `ZeroCoupled.Gen.PageGenerator` in isolation — the payoff of committed
  codegen over the old `@before_compile` macro: the generator is a plain
  function with plain inputs, so it can be unit-tested without a page
  compiling.

  `Alpha` emits a fact whose payload vocabulary (`:widget`) differs from
  the reactor's port (`:item`), so the manifest carries a `transform:` —
  the generator must splice its source into the emitted clause.
  """

  defmodule Alpha do
    defmodule Facts do
      defmodule Made do
        @enforce_keys [:widget]
        defstruct [:widget]
      end
    end

    defmodule Intents do
      use ZeroCoupled.Feature.Intents, slot: :alpha
      intent(:make, params: [n: :int])

      def make(session, %{n: n}) do
        {put_slot(session, %{count: 1}), [], [%Facts.Made{widget: n}]}
      end
    end

    def init(_opts), do: %{count: 0}
  end

  defmodule Beta do
    # Reaction-only feature: no intents, so its Intents module needs no
    # metadata macro (the generator simply collects nothing from it).
    defmodule Intents do
      def receive_item(state, %{item: item}), do: {Map.put(state, :last, item), []}
    end

    def init(_opts), do: %{last: nil}
  end

  defmodule View do
    def render(assigns), do: assigns
  end

  defmodule Page.Manifest do
    alias ZeroCoupled.GenFixtures.{Alpha, Beta, View}

    def features, do: [alpha: Alpha, beta: Beta]

    def reactions do
      [
        {Alpha.Facts.Made, to: {:beta, Beta.Intents, :receive_item, transform: &%{item: &1.widget}}}
      ]
    end

    def action_views, do: [index: View]

    # A tiny flow exercising the V33 channel: milestones, transitions,
    # URL-bound steps (and one step, :done, with no URL).
    def flows do
      [
        wizard: [
          initial: :one,
          milestones: [one: "One", two: "Two"],
          transitions: [{:one, :go, :two}, {:two, :back, :one}, {:two, :finish, :done}],
          paths: [one: "/w", two: "/w/two"]
        ]
      ]
    end
  end
end
