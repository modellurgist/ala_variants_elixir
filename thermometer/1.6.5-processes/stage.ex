# A generic execution model: a process hosting any Step, forwarding emissions to its
# wired output. Used only where the concept is really concurrent.
defmodule Stage do
  use GenServer

  def new(step) do
    {:ok, pid} = GenServer.start_link(__MODULE__, step)
    pid
  end

  def wire_in(from, to) do
    :ok = GenServer.call(from, {:wire, to})
    to
  end

  def push(nil, _data), do: :ok
  def push(pid, data), do: GenServer.cast(pid, {:push, data})

  @impl true
  def init(step), do: {:ok, %{step: step, out: nil}}

  @impl true
  def handle_call({:wire, to}, _from, st), do: {:reply, :ok, %{st | out: to}}

  @impl true
  def handle_cast({:push, data}, st) do
    case Step.push(st.step, data) do
      {:emit, out, step} ->
        push(st.out, out)
        {:noreply, %{st | step: step}}

      {:quiet, step} ->
        {:noreply, %{st | step: step}}
    end
  end
end
