defmodule ZeroCoupledWeb.Paradigms.Binder do
  @moduledoc """
  Runs a page as a composition of stories (Spray's features, §2.2), each with a bindings map that is
  its diagram as a value. A story's map says where each of its parts' ports, and each of its own
  input ports (`{:in, port}`), goes. The page is the root story, under `:page`: its map says where
  each story's outputs go, from `{story, port}`, and where its own `{:page, :mounted}` goes. Every
  step runs in the page process. Knows LiveView and the binding kinds; never a page, a story, or a
  product.

  Binding kinds:

      {:input, part, fun}          run `fun.(state, payload)` on this story's part, then deliver its outputs
      {:out, port}                 send the payload out of this story, to the page's bindings
      {:to, story, port}           (on the page) deliver the payload to a story's input port
      {:stream, name}              row changes: {:added | :changed, row}, {:removed, row}, {:reset, rows}
      {:show, field}               the payload becomes a value this story's view shows (an assign, on the page)
      {:set, field, value}         a fixed value, the same way
      {:form, field}               the payload is a changeset; it becomes a form the view shows
      {:flash, level, text}        a fixed message
      {:flash_for, level, texts}   the message under the payload's key, if any
      {:via, callee, targets}      deliver a `Call` instance's answer to `targets`
      {:via, fun, type, targets}   deliver a function's answer, of the declared type, to `targets`
      {:call, callee}              ask the callee, for its effect only
      {:async, callee, ok, error}  ask a `Call` instance in a task; its answer arrives at input `ok`,
                                   an error or a crash at input `error`
      {:start_timer, name, ms, port}  after `ms`, the payload arrives at this story's input `port`
      {:stop_timer, name}          cancel it
      {:patch, paths}              push_patch to `paths[payload]`, when the step has a URL
      :redirect                    redirect(external: payload)

  `mount/2` has `ZeroCoupledWeb.Paradigms.Diagram` check every map's types and coverage first.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3, to_form: 2]
  alias ZeroCoupled.Ports.Call
  alias ZeroCoupledWeb.Paradigms.Diagram

  @doc "What a story module provides, besides its `new/1` and its view's function components."
  @callback parts() :: %{atom => module}
  @callback ports() :: %{in: keyword, out: keyword}
  @callback events() :: [String.t()]
  @callback streams() :: [atom]
  @callback event(Phoenix.LiveView.Socket.t(), atom, String.t(), map) ::
              Phoenix.LiveView.Socket.t()

  defstruct [:module, parts: %{}, view: %{}, bindings: %{}]

  @doc "A story: its module (with `ports/0`, `events/0`, `streams/0`), parts, bindings and view."
  def story(module, parts, bindings, view \\ []),
    do: %__MODULE__{module: module, parts: parts, bindings: bindings, view: Map.new(view)}

  @doc """
  Place a composition `{page, stories}`: the page (the root story, under `:page`) and its stories,
  with each story's streams. An unsound composition (see `Diagram`) raises here, before it runs.
  """
  def mount(socket, composition) do
    {page, stories} = Diagram.check!(composition)

    Enum.reduce(stories, assign(socket, :page, page), fn {key, story}, s ->
      s = assign(s, key, story)
      Enum.reduce(story.module.streams(), s, &stream(&2, &1, [], []))
    end)
  end

  @doc "Run one step of part `part` of story `owner`, and deliver its outputs along the story's map."
  def run(socket, owner, part, step) do
    story = socket.assigns[owner]
    {state, outputs} = step.(story.parts[part])
    socket = assign(socket, owner, %{story | parts: Map.put(story.parts, part, state)})

    Enum.reduce(outputs, socket, fn {port, payload}, s ->
      deliver(s, owner, {part, port}, payload)
    end)
  end

  @doc "Send a payload out of story `owner` on `port`, to the page's bindings."
  def send_out(socket, owner, port, payload), do: deliver(socket, :page, {owner, port}, payload)

  @doc "Deliver a payload to story `owner`'s input port."
  def input(socket, owner, port, payload), do: deliver(socket, owner, {:in, port}, payload)

  @doc "Deliver a payload from `source` along story `owner`'s bindings."
  def deliver(socket, owner, source, payload) do
    socket.assigns[owner].bindings
    |> Map.get(source, [])
    |> Enum.reduce(socket, &bind(&1, owner, payload, &2))
  end

  @doc "Hand a browser event to the story among `keys` whose view emits it."
  def event(socket, keys, name, params) do
    case Enum.find(keys, &(name in socket.assigns[&1].module.events())) do
      nil -> raise ArgumentError, "no story on this page handles the event #{inspect(name)}"
      key -> socket.assigns[key].module.event(socket, key, name, params)
    end
  end

  @doc "Deliver a story task's outcome to the input its `:async` binding named."
  def async_result(socket, {:story_async, owner, ok, _}, {:ok, {:ok, answer}}),
    do: input(socket, owner, ok, answer)

  def async_result(socket, {:story_async, owner, _, error}, {:ok, {:error, reason}}),
    do: input(socket, owner, error, reason)

  def async_result(socket, {:story_async, owner, _, error}, {:exit, reason}),
    do: input(socket, owner, error, reason)

  defp bind({:input, part, fun}, owner, payload, s), do: run(s, owner, part, &fun.(&1, payload))
  defp bind({:out, port}, owner, payload, s), do: deliver(s, :page, {owner, port}, payload)
  defp bind({:to, story, port}, _owner, payload, s), do: input(s, story, port, payload)
  defp bind({:stream, name}, _o, {:added, row}, s), do: stream_insert(s, name, row)
  defp bind({:stream, name}, _o, {:changed, row}, s), do: stream_insert(s, name, row)
  defp bind({:stream, name}, _o, {:removed, row}, s), do: stream_delete(s, name, row)
  defp bind({:stream, name}, _o, {:reset, rows}, s), do: stream(s, name, rows, reset: true)
  defp bind({:show, field}, owner, payload, s), do: show(s, owner, field, payload)
  defp bind({:set, field, value}, owner, _payload, s), do: show(s, owner, field, value)

  defp bind({:form, field}, owner, changeset, s),
    do: show(s, owner, field, to_form(changeset, action: :validate))

  defp bind({:flash, level, text}, _o, _payload, s), do: put_flash(s, level, text)

  defp bind({:flash_for, level, texts}, _o, payload, s) do
    case Map.fetch(texts, payload) do
      {:ok, text} -> put_flash(s, level, text)
      :error -> s
    end
  end

  defp bind({:via, callee, targets}, owner, payload, s),
    do: answer_to(s, owner, callee, payload, targets)

  defp bind({:via, fun, _type, targets}, owner, payload, s),
    do: answer_to(s, owner, fun, payload, targets)

  defp bind({:call, callee}, _o, payload, s) do
    ask(callee, payload)
    s
  end

  defp bind({:async, callee, ok, error}, owner, payload, s),
    do: start_async(s, {:story_async, owner, ok, error}, fn -> ask(callee, payload) end)

  defp bind({:start_timer, name, ms, port}, owner, payload, s) do
    s = cancel_timer(s, name)
    ref = Process.send_after(self(), {:story_input, owner, port, payload}, ms)
    assign(s, :timers, Map.put(timers(s), name, ref))
  end

  defp bind({:stop_timer, name}, _o, _payload, s), do: cancel_timer(s, name)

  defp bind({:patch, paths}, _o, step, s) do
    case Map.fetch(paths, step) do
      {:ok, path} -> push_patch(s, to: path)
      :error -> s
    end
  end

  defp bind(:redirect, _o, url, s), do: redirect(s, external: url)

  defp answer_to(s, owner, callee, payload, targets) do
    answer = ask(callee, payload)
    Enum.reduce(targets, s, &bind(&1, owner, answer, &2))
  end

  # the page's own values are assigns; a story's are in its view
  defp show(s, :page, field, value), do: assign(s, field, value)

  defp show(s, owner, field, value) do
    story = s.assigns[owner]
    assign(s, owner, %{story | view: Map.put(story.view, field, value)})
  end

  defp ask(fun, payload) when is_function(fun, 1), do: fun.(payload)
  defp ask(fun, _payload) when is_function(fun, 0), do: fun.()
  defp ask(instance, payload), do: Call.call(instance, payload)

  defp cancel_timer(s, name) do
    case Map.pop(timers(s), name) do
      {nil, _} ->
        s

      {ref, rest} ->
        Process.cancel_timer(ref)
        assign(s, :timers, rest)
    end
  end

  defp timers(s), do: s.assigns[:timers] || %{}
end
