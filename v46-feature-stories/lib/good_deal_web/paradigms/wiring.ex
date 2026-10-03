defmodule GoodDealWeb.Paradigms.Wiring do
  @moduledoc """
  Checks that a page's `wire/3` clauses wire every port its features declare, and nothing else.
  A page lists its features with `features/0` (`%{key => FeatureModule}`); each feature declares
  `ports/0`. `gaps/1` reads the page's own source (from its compile info), so a page's coverage test
  is one line:

      assert Wiring.gaps(CartLive.Show) == %{unwired: [], unknown: []}

  Optionally, `use GoodDealWeb.Paradigms.Wiring` makes the same check at compile time, reading the
  page's `@features` attribute (which its `features/0` returns): the build fails on a gap.

  A story (a module with `parts/0`) is checked the same way one level in: `story_gaps/1` compares its
  `wire/4` heads with its parts' ports, its `input/4` heads with its own input ports, and its
  `event/4` heads with the events its view emits. `event_clashes/1` lists events two of a page's
  stories both claim.
  """

  @doc "`%{unwired: [{key, port}], unknown: [{key, port}]}` for a page module."
  def gaps(page) do
    page.__info__(:compile)[:source]
    |> to_string()
    |> File.read!()
    |> Code.string_to_quoted!()
    |> heads()
    |> compare(page.features())
  end

  @doc "The `{key, port}` of every `wire/3` clause head in quoted source."
  def heads(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {kind, _, [{:wire, _, [_, key, {port, _}]} | _]} = node, acc when kind in [:def, :defp] ->
          {node, [{key, port} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  @doc "Every list empty when a story wires each part port, handles each input, and each event it emits."
  def story_gaps(story) do
    ast = source_ast(story)
    wired = clause_args(ast, :wire, fn [_, _, part, {port, _}] -> {part, port} end)

    declared =
      for {part, mod} <- story.parts(), port <- Keyword.keys(mod.ports().out), do: {part, port}

    inputs = clause_args(ast, :input, fn [_, _, port, _] -> port end)
    events = clause_args(ast, :event, fn [_, _, name, _] -> name end)
    in_ports = Keyword.keys(story.ports().in)

    %{
      unwired: declared -- wired,
      unknown: Enum.uniq(wired) -- declared,
      inputs_unhandled: in_ports -- inputs,
      inputs_undeclared: Enum.uniq(inputs) -- in_ports,
      events_unhandled: story.events() -- events,
      events_undeclared: Enum.uniq(events) -- story.events()
    }
  end

  @doc "Events claimed by more than one of a page's stories (`features/0` entries that have `events/0`)."
  def event_clashes(page) do
    page.features()
    |> Map.values()
    |> Enum.filter(&function_exported?(&1, :events, 0))
    |> Enum.flat_map(& &1.events())
    |> Enum.frequencies()
    |> Enum.filter(fn {_, n} -> n > 1 end)
    |> Enum.map(&elem(&1, 0))
  end

  defp source_ast(module),
    do:
      module.__info__(:compile)[:source]
      |> to_string()
      |> File.read!()
      |> Code.string_to_quoted!()

  # what `pick` takes from the arguments of each `def`/`defp name(...)` head it matches
  defp clause_args(ast, name, pick) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {kind, _, [{:when, _, [{^name, _, args} | _]} | _]} = node, acc
        when kind in [:def, :defp] ->
          {node, picked(pick, args, acc)}

        {kind, _, [{^name, _, args} | _]} = node, acc when kind in [:def, :defp] ->
          {node, picked(pick, args, acc)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp picked(pick, args, acc) do
    [pick.(args) | acc]
  rescue
    FunctionClauseError -> acc
  end

  def compare(wired, features) do
    declared =
      for {key, feature} <- features, port <- Keyword.keys(feature.ports().out), do: {key, port}

    %{unwired: declared -- wired, unknown: Enum.uniq(wired) -- declared}
  end

  defmacro __using__(_opts) do
    quote do
      @on_definition GoodDealWeb.Paradigms.Wiring
      @before_compile GoodDealWeb.Paradigms.Wiring
      Module.register_attribute(__MODULE__, :wired_ports, accumulate: true)
    end
  end

  def __on_definition__(env, kind, :wire, [_, key, {port, _}], _guards, _body)
      when kind in [:def, :defp],
      do: Module.put_attribute(env.module, :wired_ports, {key, port})

  def __on_definition__(_env, _kind, _name, _args, _guards, _body), do: :ok

  defmacro __before_compile__(env) do
    wired = Module.get_attribute(env.module, :wired_ports)
    features = Module.get_attribute(env.module, :features) || %{}
    Enum.each(features, fn {_, feature} -> Code.ensure_compiled!(feature) end)

    case compare(wired, features) do
      %{unwired: [], unknown: []} ->
        :ok

      gaps ->
        raise CompileError,
          file: env.file,
          line: 0,
          description: "wire/3 wiring gaps in #{inspect(env.module)}: #{inspect(gaps)}"
    end

    nil
  end
end
