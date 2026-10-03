defmodule ZeroCoupledWeb.Paradigms.Diagram do
  @moduledoc """
  Checks and draws a page's composition: the page (the root story) and its stories, each a value
  with its `module`, its `bindings` map and its parts. Every port has a type, and a binding joins two ports of the same type: an output to
  an input, a `Call` instance's accepted payload to its answer, or a sink to the type it shows (a
  stream takes `:row_change`, a form `:changeset`, a patch `:step`, a redirect `:url`). An input typed
  `:event` takes any payload. Every output is bound or grounded, every declared input is bound, and no
  binding holds an anonymous function. `mermaid/1` draws the same value the page runs.

  A story's module provides `parts/0` (`%{part => module with ports/0}`), `ports/0` and, optionally,
  `grounded/0` (the `{part, port}` sources it leaves unbound on purpose). The page's module does the
  same, with its stories' outputs as `{story, port}` sources.
  """
  alias ZeroCoupled.Ports.Call

  @sinks %{stream: :row_change, form: :changeset, patch: :step}

  @doc "Every problem in a composition `{page, stories}`, as text; `[]` when it's sound."
  def problems({page, stories}) do
    owners = Map.put(stories, :page, page)

    for {key, owner} <- owners, problem <- owner_problems(key, owner, owners), do: problem
  end

  @doc "Raise unless the composition is sound; return it."
  def check!(composition) do
    case problems(composition) do
      [] -> composition
      found -> raise ArgumentError, "unsound composition:\n  " <> Enum.join(found, "\n  ")
    end
  end

  defp owner_problems(key, owner, owners) do
    sources = sources(key, owner, owners)

    grounded =
      if function_exported?(owner.module, :grounded, 0), do: owner.module.grounded(), else: []

    unknown =
      for {source, _} <- owner.bindings,
          not Map.has_key?(sources, source),
          do: "#{key}: binds #{label(source)}, which isn't a port"

    unbound =
      for {source, _} <- sources,
          not Map.has_key?(owner.bindings, source),
          source not in grounded,
          do: "#{key}: #{label(source)} is neither bound nor grounded"

    mistyped =
      for {source, targets} <- owner.bindings,
          type = sources[source],
          type != nil,
          target <- targets,
          problem <- target_problems(target, type, key, owner, owners),
          do: "#{key}: #{label(source)} (#{type}) → #{problem}"

    unknown ++ unbound ++ mistyped
  end

  # every port that can be a binding's source in this owner, with its type
  defp sources(key, owner, owners) do
    own_ins = if key == :page, do: [], else: owner.module.ports().in
    own_outs = if key == :page, do: owner.module.ports().out, else: []

    stories_outs =
      if key == :page,
        do:
          for(
            {k, s} <- owners,
            k != :page,
            {port, type} <- s.module.ports().out,
            do: {{k, port}, type}
          ),
        else: []

    Map.new(
      for(
        {part, mod} <- owner.module.parts(),
        {port, type} <- mod.ports().out,
        do: {{part, port}, type}
      ) ++
        for({port, type} <- own_ins, do: {{:in, port}, type}) ++
        for({port, type} <- own_outs, do: {{:page, port}, type}) ++ stories_outs
    )
  end

  defp target_problems({:input, part, fun}, type, _key, owner, _owners) do
    with {:ok, mod} <- Map.fetch(owner.module.parts(), part),
         :ok <- named(fun),
         {:ok, in_type} <- Keyword.fetch(mod.ports().in, Function.info(fun)[:name]) do
      fits(type, in_type, "#{part}.#{Function.info(fun)[:name]}")
    else
      :error -> ["#{part} has no input #{inspect(fun)}"]
      {:error, why} -> [why]
    end
  end

  defp target_problems({:out, port}, type, key, owner, _owners),
    do: port_fits(owner.module.ports().out, port, type, "#{key}'s output #{port}")

  defp target_problems({:to, story, port}, type, _key, _owner, owners) do
    case Map.fetch(owners, story) do
      {:ok, s} -> port_fits(s.module.ports().in, port, type, "#{story}'s input #{port}")
      :error -> ["no story #{story}"]
    end
  end

  defp target_problems({kind, _}, type, _k, _o, _os) when is_map_key(@sinks, kind),
    do: fits(type, @sinks[kind], "a #{kind}")

  defp target_problems(:redirect, type, _k, _o, _os), do: fits(type, :url, "a redirect")

  defp target_problems({:via, callee, targets}, type, key, owner, owners) do
    case answer(callee, type) do
      {:ok, answer} -> Enum.flat_map(targets, &target_problems(&1, answer, key, owner, owners))
      {:error, why} -> [why]
    end
  end

  defp target_problems({:via, fun, answer, targets}, _type, key, owner, owners) do
    case named(fun) do
      :ok -> Enum.flat_map(targets, &target_problems(&1, answer, key, owner, owners))
      {:error, why} -> [why]
    end
  end

  defp target_problems({:call, fun}, _type, _k, _o, _os) when is_function(fun) do
    case named(fun) do
      :ok -> []
      {:error, why} -> [why]
    end
  end

  defp target_problems({:call, callee}, type, _k, _o, _os) do
    case answer(callee, type) do
      {:ok, _} -> []
      {:error, why} -> [why]
    end
  end

  defp target_problems({:async, callee, ok, error}, type, key, owner, _owners) do
    case answer(callee, type) do
      {:ok, answer} ->
        port_fits(owner.module.ports().in, ok, answer, "#{key}'s input #{ok}") ++
          port_fits(owner.module.ports().in, error, :reason, "#{key}'s input #{error}")

      {:error, why} ->
        [why]
    end
  end

  defp target_problems({:start_timer, _name, _ms, port}, type, key, owner, _owners),
    do: port_fits(owner.module.ports().in, port, type, "#{key}'s input #{port}")

  defp target_problems(_sink, _type, _k, _o, _os), do: []

  defp port_fits(ports, port, type, what) do
    case Keyword.fetch(ports, port) do
      {:ok, in_type} -> fits(type, in_type, what)
      :error -> ["#{what} isn't declared"]
    end
  end

  defp fits(type, in_type, _what) when type == in_type or in_type in [:any, :event], do: []
  defp fits(type, in_type, what), do: ["#{what} takes #{in_type}, not #{type}"]

  defp answer(callee, _type) when is_function(callee),
    do: {:error, "#{inspect(callee)} needs a declared answer type: {:via, fun, type, targets}"}

  defp answer(callee, type) do
    case Map.fetch(Call.types(callee), type) do
      {:ok, answer} -> {:ok, answer}
      :error -> {:error, "#{inspect(callee.__struct__)} doesn't accept #{type}"}
    end
  end

  defp named(fun) do
    if String.starts_with?(to_string(Function.info(fun)[:name]), "-"),
      do: {:error, "an anonymous function hides a call; use a named capture"},
      else: :ok
  end

  defp label({a, b}), do: "#{a}.#{b}"

  @doc "A Mermaid flowchart of the page's stories and the links between them."
  def mermaid({page, stories}) do
    nodes = for {key, s} <- Enum.sort(stories), do: ~s(  #{key}["#{key}<br/>#{short(s.module)}"])

    edges =
      for {{from, port}, targets} <- Enum.sort(page.bindings), target <- targets do
        case target do
          {:to, story, input} -> ~s(  #{node_id(from)} -->|"#{port} → #{input}"| #{story})
          other -> ~s(  #{node_id(from)} -.->|"#{port}"| #{sink_node("page", other)})
        end
      end

    Enum.join(["flowchart LR" | nodes ++ Enum.uniq(edges)], "\n") <> "\n"
  end

  @doc "A Mermaid flowchart of one story's parts, its inputs and outputs, and where each port goes."
  def mermaid_story(key, story) do
    nodes =
      for {part, mod} <- Enum.sort(story.module.parts()),
          do: ~s(  #{part}["#{part}<br/>#{short(mod)}"])

    edges =
      for {{from, port}, targets} <- Enum.sort(story.bindings), target <- targets do
        source = if from == :in, do: "in_#{port}((#{port}))", else: from
        story_edge(source, port, target)
      end

    Enum.join(["flowchart LR", ~s(  %% #{key})] ++ nodes ++ Enum.uniq(edges), "\n") <> "\n"
  end

  defp story_edge(source, port, {:input, part, fun}),
    do: ~s(  #{source} -->|"#{port} → #{Function.info(fun)[:name]}"| #{part})

  defp story_edge(source, port, {:out, out}),
    do: "  #{source} -->|\"#{port}\"| out_#{out}((#{out}))"

  defp story_edge(source, port, {:via, callee, targets}),
    do:
      Enum.map_join(targets, "\n", &story_edge(source, "#{port} via #{callee_name(callee)}", &1))

  defp story_edge(source, port, {:via, fun, _type, targets}),
    do: Enum.map_join(targets, "\n", &story_edge(source, "#{port} via #{callee_name(fun)}", &1))

  defp story_edge(source, port, other),
    do: ~s(  #{source} -.->|"#{port}"| #{sink_node("view", other)})

  defp node_id(:page), do: "page"
  defp node_id(key), do: key

  # one node per kind of sink, and per instance for the ones that do I/O
  defp sink_node(prefix, {:call, callee}),
    do: ~s(#{prefix}_call_#{callee_name(callee)}["call #{callee_name(callee)}"])

  defp sink_node(prefix, {:async, callee, ok, error}),
    do:
      ~s(#{prefix}_task_#{callee_name(callee)}["task #{callee_name(callee)} → #{ok} / #{error}"])

  defp sink_node(prefix, target) when is_tuple(target), do: sink_node(prefix, elem(target, 0))
  defp sink_node(prefix, kind), do: ~s(#{prefix}_#{kind}["#{prefix}: #{kind}"])

  defp callee_name(fun) when is_function(fun), do: Function.info(fun)[:name]
  defp callee_name(instance), do: short(instance.__struct__)

  defp short(module), do: module |> Module.split() |> List.last()
end
