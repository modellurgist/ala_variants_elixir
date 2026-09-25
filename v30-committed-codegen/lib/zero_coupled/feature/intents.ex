defmodule ZeroCoupled.Feature.Intents do
  @moduledoc """
  `use`-helper for a feature's `Intents` module — in V30 the **only**
  macro in the system (V29's web-layer `feature`/`react`/`action_view`
  macros are gone; the manifest is now a plain data module compiled by
  `ZeroCoupled.Gen.PageGenerator` into a committed file).

  It provides exactly three things, all inspectable:

    * `intent name, params: [...]` — **metadata only**. Records the
      intent's name and param-cast spec so the page manifest can
      generate the `handle_event` clause you would otherwise write by
      hand. It generates no behaviour of its own.
    * `put_slot/2` — writes this feature's own slot in the session
      struct (`Map.replace!/3`, so a wrong slot name raises loudly).
      The ownership rule: an intent may *read* any slot but *write*
      only its own; cross-slot writes happen via facts + manifest
      reactions.
    * `__slot__/0` and `__intents__/0` — introspection used by the
      generator (`mix zc.gen`) and by `PageCheck.verify/1` in tests.

  Intent functions are ordinary functions `(session, args) ->
  {session, effects}` or `{session, effects, facts}`. Reaction
  functions (declared in the manifest's `react` lines) are
  slot-scoped: `(slot_state, payload) -> {slot_state, effects}` —
  they never see the session at all.
  """

  @type param_type :: :int | :string | :atom

  defmacro __using__(opts) do
    slot = Keyword.fetch!(opts, :slot)

    quote do
      import ZeroCoupled.Feature.Intents, only: [intent: 1, intent: 2]

      Module.register_attribute(__MODULE__, :__intents__, accumulate: true)
      @__slot__ unquote(slot)
      @before_compile ZeroCoupled.Feature.Intents

      defp put_slot(session, value), do: Map.replace!(session, unquote(slot), value)
    end
  end

  @doc "Declare a shell-dispatchable intent and its param-cast spec."
  defmacro intent(name, opts \\ []) do
    params = Keyword.get(opts, :params, [])

    quote do
      @__intents__ {unquote(name), unquote(params)}
    end
  end

  defmacro __before_compile__(env) do
    intents = Module.get_attribute(env.module, :__intents__) |> Enum.reverse()

    quote do
      @doc false
      def __slot__, do: @__slot__

      @doc false
      def __intents__, do: unquote(Macro.escape(intents))
    end
  end
end
