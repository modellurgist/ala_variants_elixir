defmodule GoodDealWeb.Paradigms.Story do
  @moduledoc """
  Runs Spray's features (user stories) on a LiveView page. A story is a module in the Features layer
  that "creates instances of domain abstractions, configures the instances with feature specific
  details, and connects them together" (Spray §2.2), keeps its own view, and has ports of its own. The
  page holds each story under a key, and its own `wire/3` connects one story's outputs to another's
  inputs.

  A story module provides:

    * `new(opts)`: a `%Story{}` holding its parts (domain state values), its configured instances
      and its view's starting values
    * `parts/0` (`%{part => module}`), `ports/0` (`%{in: [...], out: [...]}`), `events/0` (the browser
      events its view emits) and `streams/0` (the streams its view shows)
    * `input(socket, key, port, payload)`: one clause per input port
    * `event(socket, key, name, params)`: one clause per event, decoding params at the edge
    * `wire(socket, key, part, {port, payload})`: one clause per part port, the story's inner wiring

  A story's timers and async tasks report back to its own input ports, so a page needs one generic
  clause for each (`handle_info({:story_input, ...})`, `handle_async({:story_async, ...})`) and knows
  no timer or task names. Knows LiveView and this convention; never a page or a story.
  """

  @callback parts() :: %{atom => module}
  @callback ports() :: %{in: keyword, out: keyword}
  @callback events() :: [String.t()]
  @callback streams() :: [atom]
  @callback input(Phoenix.LiveView.Socket.t(), atom, atom, term) :: Phoenix.LiveView.Socket.t()
  @callback event(Phoenix.LiveView.Socket.t(), atom, String.t(), map) ::
              Phoenix.LiveView.Socket.t()
  @callback wire(Phoenix.LiveView.Socket.t(), atom, atom, {atom, term}) ::
              Phoenix.LiveView.Socket.t()
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4, start_async: 3]

  alias GoodDealWeb.Paradigms.Sinks

  defstruct [:module, parts: %{}, instances: %{}, timers: %{}, view: %{}]

  def new(module, parts, opts \\ []),
    do: %__MODULE__{
      module: module,
      parts: parts,
      instances: Keyword.get(opts, :instances, %{}),
      timers: Keyword.get(opts, :timers, %{}),
      view: Map.new(Keyword.get(opts, :view, []))
    }

  @doc "Place the page's stories, and the page's `wire/3`, which every story's outputs go through."
  def mount(socket, stories, page_wire) do
    socket = assign(socket, :page_wire, page_wire)

    Enum.reduce(stories, socket, fn {key, story}, s ->
      s = assign(s, key, story)
      Enum.reduce(story.module.streams(), s, &stream(&2, &1, [], []))
    end)
  end

  @doc "Run one step of part `part` of story `key`, and wire its outputs through the story."
  def run(socket, key, part, step) do
    story = socket.assigns[key]
    {state, outputs} = step.(story.parts[part])
    socket = assign(socket, key, %{story | parts: Map.put(story.parts, part, state)})
    Enum.reduce(outputs, socket, &story.module.wire(&2, key, part, &1))
  end

  @doc "Run part `part`'s `input` on what `source` answers for `payload`."
  def feed(socket, key, part, input, source, payload),
    do: run(socket, key, part, &input.(&1, ask(socket, key, source, payload)))

  @doc "Send what `source` answers for `payload` out of the story on `port`."
  def send_out_answer(socket, key, port, source, payload),
    do: send_out(socket, key, port, ask(socket, key, source, payload))

  @doc "Ask `source` for its effect only."
  def call(socket, key, source, payload) do
    ask(socket, key, source, payload)
    socket
  end

  @doc """
  Ask one of the story's instances in a `start_async` task. Its `{:ok, answer}` goes to the story's
  input `ok`, and an `{:error, reason}` or a crash to its input `error`.
  """
  def async(socket, key, {instance, fun}, payload, ok: ok, error: error) do
    configured = instance!(socket, key, instance)
    start_async(socket, {:story_async, key, ok, error}, fn -> fun.(configured, payload) end)
  end

  @doc "Deliver a story task's outcome to the input `async/6` named for it."
  def async_result(socket, {:story_async, key, ok, _}, {:ok, {:ok, answer}}),
    do: input(socket, key, ok, answer)

  def async_result(socket, {:story_async, key, _, error}, {:ok, {:error, reason}}),
    do: input(socket, key, error, reason)

  def async_result(socket, {:story_async, key, _, error}, {:exit, reason}),
    do: input(socket, key, error, reason)

  @doc "Send a port output of story `key` to the page's wiring."
  def send_out(socket, key, port, payload),
    do: socket.assigns.page_wire.(socket, key, {port, payload})

  @doc """
  Start the story's timer `name`. It was configured as `{ms, port}`: after `ms`, `payload` arrives at
  the story's input `port`, through the page's `handle_info({:story_input, ...})`.
  """
  def start_timer(socket, key, name, payload) do
    {ms, port} = Map.fetch!(socket.assigns[key].timers, name)
    Sinks.send_after(socket, name, {:story_input, key, port, payload}, ms)
  end

  @doc "Set a value the story's view shows."
  def show(socket, key, field, value) do
    story = socket.assigns[key]
    assign(socket, key, %{story | view: Map.put(story.view, field, value)})
  end

  def input(socket, key, port, payload),
    do: socket.assigns[key].module.input(socket, key, port, payload)

  @doc "Hand a browser event to the story among `keys` whose view emits it."
  def event(socket, keys, name, params) do
    case Enum.find(keys, &(name in socket.assigns[&1].module.events())) do
      nil -> raise ArgumentError, "no story on this page handles the event #{inspect(name)}"
      key -> socket.assigns[key].module.event(socket, key, name, params)
    end
  end

  defp ask(socket, key, {name, fun}, payload) when is_atom(name) and is_function(fun, 2),
    do: fun.(instance!(socket, key, name), payload)

  defp ask(_socket, _key, fun, payload) when is_function(fun, 1), do: fun.(payload)
  defp ask(_socket, _key, fun, _payload) when is_function(fun, 0), do: fun.()

  defp instance!(socket, key, name) do
    case socket.assigns[key].instances do
      %{^name => instance} ->
        instance

      _ ->
        raise ArgumentError, "story #{inspect(key)} has no configured instance #{inspect(name)}"
    end
  end
end
