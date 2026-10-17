defmodule Credo.Check.Custom.AlaLayerBoundary do
  @moduledoc """
  Enforces ALA layer boundaries at compile time via static analysis.

  Each layer in an ALA architecture has a restricted set of modules it
  may reference. This check walks the AST of every source file, determines
  which layer the file belongs to (by its path), and flags any `alias`,
  `import`, `use`, or `require` that references a module in a forbidden
  layer.

  ## Configuration

  Pass a `layers` list in `.credo.exs`:

      {Credo.Check.Custom.AlaLayerBoundary, [
        layers: [
          %{
            name: "Domain",
            path: "lib/good_deal/domain/",
            forbidden_prefixes: ["GoodDeal.Foundation", "GoodDealWeb", "Phoenix"]
          },
          ...
        ]
      ]}

  Each entry maps a directory path prefix to a list of module name prefixes
  that files in that directory must not reference.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [layers: []]

  alias Credo.Code

  @impl true
  def run(%Credo.SourceFile{} = source_file, params) do
    layers = Params.get(params, :layers, __MODULE__)
    file_path = source_file.filename

    case find_layer(file_path, layers) do
      nil ->
        []

      layer ->
        forbidden = Map.get(layer, :forbidden_prefixes, [])
        layer_name = Map.get(layer, :name, layer.path)

        source_file
        |> Code.ast()
        |> collect_references()
        |> Enum.flat_map(fn {module_string, line} ->
          case find_violation(module_string, forbidden) do
            nil ->
              []

            prefix ->
              [issue_for(source_file, params, module_string, prefix, layer_name, line)]
          end
        end)
    end
  end

  defp find_layer(file_path, layers) do
    Enum.find(layers, fn layer ->
      String.contains?(file_path, layer.path)
    end)
  end

  defp find_violation(module_string, forbidden_prefixes) do
    Enum.find(forbidden_prefixes, fn prefix ->
      String.starts_with?(module_string, prefix)
    end)
  end

  defp collect_references({:ok, ast}) do
    {_, refs} =
      Macro.prewalk(ast, [], fn
        {:alias, meta, [{:__aliases__, _, parts} | _]} = node, acc ->
          module = Enum.map_join(parts, ".", &to_string/1)
          {node, [{module, meta[:line] || 0} | acc]}

        {:alias, meta, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, groups}]} = node, acc ->
          base_str = Enum.map_join(base, ".", &to_string/1)

          new_refs =
            Enum.map(groups, fn {:__aliases__, _, parts} ->
              full = base_str <> "." <> Enum.map_join(parts, ".", &to_string/1)
              {full, meta[:line] || 0}
            end)

          {node, new_refs ++ acc}

        {directive, meta, [{:__aliases__, _, parts} | _]} = node, acc
        when directive in [:import, :use, :require] ->
          module = Enum.map_join(parts, ".", &to_string/1)
          {node, [{module, meta[:line] || 0} | acc]}

        node, acc ->
          {node, acc}
      end)

    refs
  end

  defp collect_references(_), do: []

  defp issue_for(source_file, params, module_string, forbidden_prefix, layer_name, line) do
    format_issue(
      source_file,
      message:
        "ALA layer violation: #{layer_name} module must not reference `#{module_string}` " <>
          "(forbidden prefix: #{forbidden_prefix})",
      trigger: module_string,
      line_no: line,
      params: params
    )
  end
end
