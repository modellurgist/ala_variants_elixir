# Spray 1.6.5 with processes: each instance is a process with an output port, wired
# from above. The literal translation; use it where the concept is really concurrent.
Code.require_file("dataflow.exs", __DIR__)

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

defmodule Thermometer do
  def start do
    program = Stage.new(%OffsetAndScale{offset: -200, scale: 0.2})

    program
    |> Stage.wire_in(Stage.new(%LowPassFilter{strength: 10, last: 40.0}))
    |> Stage.wire_in(Stage.new(%SampleEvery{n: 10}))
    |> Stage.wire_in(Stage.new(%NumberToString{decimals: 1}))
    |> Stage.wire_in(Stage.new(%Display{label: "Temperature: "}))

    program
  end
end

program = Thermometer.start()
for i <- 1..30, do: Stage.push(program, 400 + rem(i, 7))
# Casts are async; give the last stage time to print before the script exits.
Process.sleep(100)
