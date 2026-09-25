defmodule Mix.Tasks.Zc.Trace do
  @shortdoc "Print an intent's owner, params, and the page's reaction wiring"

  @moduledoc """
  The trace-locality answer — the composition's story on one screen,
  read from committed data (`__manifest__/0`):

      mix zc.trace remove_item

  Prints the intent's owning feature and param spec, plus the full
  fact → reaction table for the page it belongs to. (Which facts a given
  intent *emits* is decided at runtime inside the intent function, so
  that edge is shown as the page-wide reaction table rather than guessed
  statically.)
  """

  use Mix.Task

  @requirements ["compile"]

  @impl true
  def run([intent_name | _]) do
    name = String.to_atom(intent_name)

    page =
      discover_pages()
      |> Enum.find(fn p -> Enum.any?(p.__manifest__().intents, &(elem(&1, 0) == name)) end)

    page || Mix.raise("no page declares an intent named #{inspect(name)}")

    m = page.__manifest__()
    {^name, slot, mod, params} = Enum.find(m.intents, &(elem(&1, 0) == name))

    info("intent :#{name}")
    info("  owner:  #{slot}  (#{inspect(mod)})")
    info("  params: #{inspect(params)}")
    info("")
    info("page #{inspect(page)} reaction wiring (fact → reactions):")

    Enum.each(m.reactions, &print_reaction/1)
  end

  def run(_), do: Mix.raise("usage: mix zc.trace <intent_name>")

  defp print_reaction({fact_mod, targets}) do
    info("  #{short(fact_mod)}")
    Enum.each(targets, &print_target/1)
  end

  defp print_target({slot, mod, fun, opts}) do
    via = if opts[:transform], do: " [transform]", else: " [Map.from_struct]"
    info("    → #{slot}: #{short(mod)}.#{fun}/2#{via}")
  end

  defp discover_pages do
    Path.wildcard("lib/**/pages/*/manifest.ex")
    |> Enum.map(fn path ->
      path
      |> Path.relative_to("lib")
      |> Path.dirname()
      |> Path.split()
      |> Enum.reject(&(&1 == "pages"))
      |> Enum.map(&Macro.camelize/1)
      |> Module.concat()
    end)
  end

  defp short(mod), do: mod |> Module.split() |> Enum.take(-2) |> Enum.join(".")
  defp info(line), do: Mix.shell().info(line)
end
