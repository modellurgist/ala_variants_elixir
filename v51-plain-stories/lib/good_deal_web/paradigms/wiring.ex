defmodule GoodDealWeb.Paradigms.Wiring do
  @moduledoc """
  Checks that a composition's `wire` clauses wire every port its parts declare, and nothing else. A
  composition (a page, or a story in the Features layer) lists its parts with `parts/0`
  (`%{key => module}`); each part declares `ports/0`. A page's clauses are `wire/3`, a story's
  `wire/4` (the last argument is where the story's own outputs go), and both have the key and
  `{port, payload}` as their second and third arguments. `gaps/1` reads the composition's own source
  (from its compile info), so a coverage test is one line:

      assert Wiring.gaps(CartLive.Show) == %{unwired: [], unknown: []}

  `input_gaps/1` checks the other side of a story: an `input/4` clause for every input port it
  declares. `event_gaps/1` checks a story's browser events: every event its views emit is in its
  `events/0`, and has a `handle_event/4` clause, and nothing else is. Optionally, `use GoodDealWeb.Paradigms.Wiring` makes the `gaps/1` check at compile time,
  reading the `@parts` attribute (which `parts/0` returns): the build fails on a gap.
  """

  @doc "`%{unwired: [{key, port}], unknown: [{key, port}]}` for a page or a story."
  def gaps(composition), do: composition |> source() |> heads() |> compare(composition.parts())

  @doc "`%{unhandled: [port], unknown: [port]}`: a story's input ports without an `input/4` clause, and clauses for no port."
  def input_gaps(story) do
    handled = story |> source() |> input_heads()
    declared = Keyword.keys(story.ports().in)
    %{unhandled: declared -- handled, unknown: Enum.uniq(handled) -- declared}
  end

  @doc "`%{unhandled: [event], undeclared: [event], unused: [event]}` for a story's browser events."
  def event_gaps(story) do
    ast = source(story)
    emitted = emitted_events(ast)
    handled = collect(ast, &event_head/1)
    declared = story.events()

    %{
      unhandled: Enum.uniq(emitted ++ declared) -- handled,
      undeclared: Enum.uniq(emitted ++ handled) -- declared,
      unused: Enum.uniq(declared ++ handled) -- emitted
    }
  end

  @doc "The `{key, port}` of every `wire` clause head in quoted source."
  def heads(ast) do
    collect(ast, fn
      {kind, _, [{:wire, _, [_, key, {port, _} | _]} | _]} when kind in [:def, :defp] ->
        {key, port}

      _ ->
        nil
    end)
  end

  def compare(wired, parts) do
    declared =
      for {key, part} <- parts, port <- Keyword.keys(part.ports().out), do: {key, port}

    %{unwired: declared -- wired, unknown: Enum.uniq(wired) -- declared}
  end

  defp input_heads(ast) do
    collect(ast, fn
      {kind, _, [{:input, _, [_, port, _, _]} | _]}
      when kind in [:def, :defp] and is_atom(port) ->
        port

      _ ->
        nil
    end)
  end

  defp event_head({kind, _, [{:handle_event, _, [event, _, _, _]} | _]})
       when kind in [:def, :defp] and is_binary(event),
       do: event

  defp event_head(_), do: nil

  # the events a story's templates fire: `phx-click="..."` and the like, and the event names it
  # hands to domain UI components (`event="..."`, `on_remove="..."`)
  @event_attr ~r/(?:phx-(?:click|submit|change)|event|on_[a-z_]+)="([a-z_]+)"/

  defp emitted_events(ast) do
    collect(ast, fn
      {:sigil_H, _, [{:<<>>, _, [template]}, _]} when is_binary(template) ->
        Regex.scan(@event_attr, template, capture: :all_but_first) |> List.flatten()

      _ ->
        nil
    end)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp source(module),
    do:
      module.__info__(:compile)[:source]
      |> to_string()
      |> File.read!()
      |> Code.string_to_quoted!()

  defp collect(ast, pick) do
    {_, found} =
      Macro.prewalk(ast, [], fn node, acc ->
        case pick.(node) do
          nil -> {node, acc}
          hit -> {node, [hit | acc]}
        end
      end)

    Enum.reverse(found)
  end

  defmacro __using__(_opts) do
    quote do
      @on_definition GoodDealWeb.Paradigms.Wiring
      @before_compile GoodDealWeb.Paradigms.Wiring
      Module.register_attribute(__MODULE__, :wired_ports, accumulate: true)
    end
  end

  def __on_definition__(env, kind, :wire, [_, key, {port, _} | _], _guards, _body)
      when kind in [:def, :defp],
      do: Module.put_attribute(env.module, :wired_ports, {key, port})

  def __on_definition__(_env, _kind, _name, _args, _guards, _body), do: :ok

  defmacro __before_compile__(env) do
    wired = Module.get_attribute(env.module, :wired_ports)
    parts = Module.get_attribute(env.module, :parts) || %{}
    Enum.each(parts, fn {_, part} -> Code.ensure_compiled!(part) end)

    case compare(wired, parts) do
      %{unwired: [], unknown: []} ->
        :ok

      gaps ->
        raise CompileError,
          file: env.file,
          line: 0,
          description: "wire clause gaps in #{inspect(env.module)}: #{inspect(gaps)}"
    end

    nil
  end
end
