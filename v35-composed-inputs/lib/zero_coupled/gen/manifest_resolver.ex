defmodule ZeroCoupled.Gen.ManifestResolver do
  @moduledoc """
  Reads a page `Manifest` into the plain data the code generators consume:
  normalized feature specs, resolved reactions (with each `transform:`
  capture's source spliced from the manifest's AST), and the page's declared
  intents with single-owner enforced. Knows the manifest's shape and nothing
  about the code emitted from it — `PageGenerator` depends on this downward.
  """

  # `features/0` returns `[slot: Module | {Module, opts}]` with modules
  # already resolved. Normalize to `{slot, module, opts}`.
  def normalize_features(features) do
    for {slot, spec} <- features do
      case spec do
        {mod, opts} when is_atom(mod) and is_list(opts) -> {slot, mod, opts}
        mod when is_atom(mod) -> {slot, mod, []}
      end
    end
  end

  # Resolve reactions to `[{fact_mod, [%{slot, mod, fun, transform_ast}]}]`.
  # Modules come from calling `reactions/0` (compiler-resolved aliases);
  # transform source comes from the manifest file's AST, consumed in the
  # same document order the runtime list presents.
  def resolve_reactions(manifest_mod) do
    transforms = transform_asts(manifest_mod)

    {normalized, leftover} =
      Enum.map_reduce(manifest_mod.reactions(), transforms, fn {fact_mod, opts}, ts ->
        targets = opts |> Keyword.fetch!(:to) |> List.wrap()
        {norm, ts} = Enum.map_reduce(targets, ts, &normalize_target/2)
        {{fact_mod, norm}, ts}
      end)

    unless leftover == [], do: raise("transform/target mismatch generating #{inspect(manifest_mod)}")
    normalized
  end

  # Collect declared intents from each feature's Intents module and
  # enforce single ownership (one intent → one feature).
  def collect_intents!(features) do
    intents =
      for {slot, mod, _opts} <- features,
          intents_mod = Module.concat(mod, Intents),
          match?({:module, _}, Code.ensure_compiled(intents_mod)),
          function_exported?(intents_mod, :__intents__, 0),
          {name, params} <- intents_mod.__intents__() do
        {name, slot, intents_mod, params}
      end

    intents
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.each(fn {name, owners} ->
      if length(owners) > 1 do
        slots = Enum.map(owners, &elem(&1, 1))

        raise "intent #{inspect(name)} is declared by multiple features #{inspect(slots)}; " <>
                "every intent must have exactly one owner"
      end
    end)

    intents
  end

  # A 3-tuple target takes the default projection; a 4-tuple with a
  # `transform:` consumes the next transform AST (source order).
  defp normalize_target({slot, mod, fun}, ts),
    do: {%{slot: slot, mod: mod, fun: fun, transform_ast: nil}, ts}

  defp normalize_target({slot, mod, fun, kw}, ts) when is_list(kw) do
    if Keyword.has_key?(kw, :transform) do
      [t | rest] = ts
      {%{slot: slot, mod: mod, fun: fun, transform_ast: t}, rest}
    else
      {%{slot: slot, mod: mod, fun: fun, transform_ast: nil}, ts}
    end
  end

  # Every `transform:` capture in `reactions/0`, in source order.
  defp transform_asts(manifest_mod) do
    source =
      manifest_mod.module_info(:compile)[:source] |> to_string() |> File.read!()

    ast = Code.string_to_quoted!(source)
    body = def_body(ast, :reactions) || raise("Manifest #{inspect(manifest_mod)} has no reactions/0")

    {_, acc} =
      Macro.prewalk(body, [], fn
        {:transform, t} = node, acc -> {node, [t | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(acc)
  end

  # Find `def <name> do ... end`'s body inside a module AST.
  defp def_body(ast, name) do
    {_, found} =
      Macro.prewalk(ast, nil, fn
        {:def, _, [{^name, _, args}, [do: body]]} = node, nil when args in [nil, []] ->
          {node, body}

        node, acc ->
          {node, acc}
      end)

    found
  end
end
