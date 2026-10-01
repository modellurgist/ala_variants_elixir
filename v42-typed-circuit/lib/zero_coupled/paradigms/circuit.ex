defmodule ZeroCoupled.Paradigms.Circuit do
  @moduledoc """
  A graph of named Step instances plus wires from `{instance, port}` to `{instance, input}`.
  Pushing into an instance delivers along the wires, depth first; outputs on unwired ports come
  back to the caller as the circuit's edge. `validate!/1` checks the wiring against each
  instance's declared ports before the circuit runs.
  """
  alias ZeroCoupled.Ports.Step
  defstruct parts: %{}, wires: %{}, grounds: []

  def new(parts), do: %__MODULE__{parts: Map.new(parts)}

  def wire(%__MODULE__{} = c, from, to),
    do: %{c | wires: Map.update(c.wires, from, [to], &(&1 ++ [to]))}

  @doc "Mark an output as deliberately unused on this page, so `validate!/1` doesn't call it dangling."
  def ground(%__MODULE__{} = c, from), do: %{c | grounds: [from | c.grounds]}

  @doc """
  Raises on a wire to or from an unknown instance or port, a wire between different paradigm types,
  an output that is neither wired nor grounded, a timer or async target that isn't a declared input,
  or an anonymous function in any instance's configuration. Returns the circuit.
  """
  def validate!(%__MODULE__{} = c) do
    problems = wire_problems(c) ++ feed_problems(c) ++ dangling(c) ++ anonymous(c)

    if problems != [],
      do: raise(ArgumentError, "invalid circuit:\n  " <> Enum.join(problems, "\n  "))

    c
  end

  def push(%__MODULE__{} = c, id, data) do
    case Step.push(Map.fetch!(c.parts, id), data) do
      {:quiet, part} ->
        {put_part(c, id, part), []}

      {:emit, outputs, part} ->
        Enum.reduce(outputs, {put_part(c, id, part), []}, &route(&1, id, &2))
    end
  end

  def part(%__MODULE__{parts: parts}, id), do: Map.fetch!(parts, id)

  defp route({port, payload}, id, {c, edge}) do
    case Map.get(c.wires, {id, port}, []) do
      [] ->
        {c, edge ++ [{{id, port}, payload}]}

      targets ->
        Enum.reduce(targets, {c, edge}, fn {to, input}, {c, edge} ->
          {c2, more} = push(c, to, {input, payload})
          {c2, edge ++ more}
        end)
    end
  end

  defp put_part(c, id, part), do: %{c | parts: Map.put(c.parts, id, part)}

  defp wire_problems(c) do
    for {{from, port}, targets} <- c.wires,
        {to, input} <- targets,
        problem = check(c, from, port, to, input),
        do: problem
  end

  defp check(c, from, port, to, input) do
    with {:ok, out} <- port_type(c, from, :out, port),
         {:ok, in_type} <- port_type(c, to, :in, input) do
      if out == in_type or :any in [out, in_type],
        do: nil,
        else: "#{from}.#{port} (#{out}) -> #{to}.#{input} (#{in_type})"
    else
      {:error, why} -> why
    end
  end

  defp feed_problems(c) do
    for {id, part} <- c.parts,
        {to, input} <- Step.feeds(part),
        problem = feed_check(c, id, to, input),
        do: problem
  end

  defp feed_check(c, id, to, input) do
    case port_type(c, to, :in, input) do
      {:ok, _} -> nil
      {:error, why} -> "#{id} feeds back into #{to}.#{input}: #{why}"
    end
  end

  defp port_type(c, id, dir, port) do
    with {:ok, part} <- fetch(c.parts, id, "no instance #{id}"),
         {:ok, type} <- fetch(Step.ports(part)[dir], port, "#{id} has no #{dir} port #{port}") do
      {:ok, type}
    end
  end

  defp fetch(map_or_list, key, why) do
    case Access.fetch(map_or_list, key) do
      {:ok, v} -> {:ok, v}
      :error -> {:error, why}
    end
  end

  defp dangling(c) do
    for {id, part} <- c.parts,
        {port, type} <- Step.ports(part).out,
        type != :ui,
        not Map.has_key?(c.wires, {id, port}),
        {id, port} not in c.grounds,
        do: "#{id}.#{port} is neither wired nor grounded"
  end

  defp anonymous(c) do
    for {id, part} <- c.parts,
        {field, f} <- Map.from_struct(part),
        is_function(f),
        String.starts_with?(Atom.to_string(Function.info(f)[:name]), "-"),
        do: "#{id}.#{field} is an anonymous function; use a named capture"
  end
end
