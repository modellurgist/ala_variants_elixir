defmodule Mix.Tasks.Circuit.Draw do
  @shortdoc "Render each page's diagram to docs/diagrams/*.mmd (--check: fail if they drifted)"
  @moduledoc """
  Renders `CartDiagram` and `PortalDiagram` to Mermaid under `docs/diagrams/`. With `--check`, fails
  instead of writing when a committed drawing differs from the diagram, so the drawing in the docs
  is always the circuit that runs.
  """
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("compile")
    check? = "--check" in args

    stale =
      for {file, text} <- ZeroCoupledWeb.Diagrams.drawings(),
          drifted?(file, text, check?),
          do: file

    if check? and stale != [],
      do:
        Mix.raise("diagram drawings are stale: #{Enum.join(stale, ", ")} (run mix circuit.draw)")
  end

  defp drifted?(file, text, true), do: File.read(file) != {:ok, text}

  defp drifted?(file, text, false) do
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, text)
    Mix.shell().info("wrote #{file}")
    false
  end
end
