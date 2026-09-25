defmodule Mix.Tasks.Zc.Gen do
  @shortdoc "Generate (or --check) a page's committed glue from its Manifest"

  @moduledoc """
  V30's diagram-first workflow: change a page's `Manifest`, then

      mix zc.gen                      # regenerate every page's generated.ex
      mix zc.gen ZeroCoupledWeb.CartPage
      mix zc.gen --check              # fail if any committed file is stale

  `--check` is wired into the `test` alias, so a forgotten regeneration
  cannot pass CI. With no module argument the task discovers pages by
  their `pages/*/manifest.ex` files.
  """

  use Mix.Task

  @requirements ["compile"]

  @impl true
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, switches: [check: :boolean])

    pages = if rest == [], do: discover_pages(), else: Enum.map(rest, &Module.concat([&1]))

    if pages == [] do
      Mix.raise("no pages found (looked for lib/**/pages/*/manifest.ex)")
    end

    Enum.each(pages, fn page -> handle(page, opts[:check] || false) end)
  end

  defp handle(page, check?) do
    source = ZeroCoupled.Gen.PageGenerator.generate(page)
    path = ZeroCoupled.Gen.PageGenerator.generated_path(page)
    rel = Path.relative_to_cwd(path)

    cond do
      check? and not File.exists?(path) ->
        Mix.raise("#{rel} is missing — run `mix zc.gen`")

      check? ->
        if File.read!(path) == source do
          Mix.shell().info("ok  #{rel}")
        else
          Mix.raise("#{rel} is stale — run `mix zc.gen` and commit the result")
        end

      true ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, source)
        Mix.shell().info("wrote #{rel}")
    end
  end

  # A page module for each lib/**/pages/<page>/manifest.ex (the `pages`
  # directory is a convention, not part of the module name).
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
end
