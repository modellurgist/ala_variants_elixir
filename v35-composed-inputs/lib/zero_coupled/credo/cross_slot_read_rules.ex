defmodule ZeroCoupled.Credo.CrossSlotReadRules do
  @moduledoc """
  R2 detector: a feature's `Intents` module must not read a **peer slot** off
  the session. It may read/write only its own slot (declared in
  `use ZeroCoupled.Feature.Intents, slot: :x`); any `session.<other_slot>`
  access is a cross-slot read — two sibling features sharing the meaning of a
  third's state, the peer/communication dependency R2 forbids. The composition
  (the page shell / manifest) is where cross-slot joins belong, so it resolves
  the value and passes it in.

  Credo-free so it doubles as a standalone measurement instrument
  (`run_cross_slot_read.exs`). AST-based: `session.<field>` is a dot access on
  the `session` var; the own slot comes from the `use` line.
  """

  @type finding :: %{module: String.t(), own_slot: atom(), slot: atom(), line: pos_integer()}

  @spec findings(String.t()) :: [finding()]
  def findings(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:ok, ast} -> scan(ast)
      {:error, _} -> []
    end
  end

  defp scan(ast) do
    {_, acc} = Macro.prewalk(ast, %{own: nil, mod: nil, findings: []}, &visit/2)
    Enum.reverse(acc.findings)
  end

  defp visit({:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc),
    do: {node, %{acc | mod: Enum.map_join(parts, ".", &to_string/1)}}

  defp visit({:use, _, [{:__aliases__, _, parts}, opts]} = node, acc) do
    if List.last(parts) == :Intents and Keyword.keyword?(opts),
      do: {node, %{acc | own: Keyword.get(opts, :slot)}},
      else: {node, acc}
  end

  defp visit({{:., meta, [{:session, _, ctx}, field]}, _, []} = node, acc)
       when is_atom(ctx) and is_atom(field) do
    if acc.own && field != acc.own do
      f = %{module: acc.mod, own_slot: acc.own, slot: field, line: meta[:line] || 0}
      {node, %{acc | findings: [f | acc.findings]}}
    else
      {node, acc}
    end
  end

  defp visit(node, acc), do: {node, acc}
end
