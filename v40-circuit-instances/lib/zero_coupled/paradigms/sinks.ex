defmodule ZeroCoupled.Paradigms.ToStream do
  @moduledoc "A sink: a collection change in, a stream operation out on `:ui`. Config: the stream name."
  defstruct [:name]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{name: n} = s, {_, {:added, row}}), do: {:emit, [ui: {:stream_insert, n, row}], s}
    def push(%{name: n} = s, {_, {:changed, row}}), do: {:emit, [ui: {:stream_insert, n, row}], s}
    def push(%{name: n} = s, {_, {:removed, row}}), do: {:emit, [ui: {:stream_delete, n, row}], s}
    def push(%{name: n} = s, {_, {:reset, rows}}), do: {:emit, [ui: {:stream_reset, n, rows}], s}
  end
end

defmodule ZeroCoupled.Paradigms.ToComponent do
  @moduledoc "A sink: anything in, a `send_update` to a UI instance out on `:ui`. Config: module and id."
  defstruct [:module, :id]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{module: m, id: id} = s, {_, change}),
      do: {:emit, [ui: {:component, m, id, change}], s}
  end
end

defmodule ZeroCoupled.Paradigms.ToAssign do
  @moduledoc "A sink: a value in, an assign out on `:ui`. Config: the name, and optionally a fixed value that replaces the payload."
  defstruct [:name, value: :payload]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{name: n, value: :payload} = s, {_, value}),
      do: {:emit, [ui: {:assign, n, value}], s}

    def push(%{name: n, value: v} = s, _), do: {:emit, [ui: {:assign, n, v}], s}
  end
end

defmodule ZeroCoupled.Paradigms.ToForm do
  @moduledoc "A sink: a changeset in, a validated form assign out on `:ui`. Config: the assign name."
  defstruct [:name]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{name: n} = s, {_, changeset}),
      do: {:emit, [ui: {:assign, n, Phoenix.Component.to_form(changeset, action: :validate)}], s}
  end
end

defmodule ZeroCoupled.Paradigms.ToFlash do
  @moduledoc "A sink: anything in, a flash out on `:ui`. Config: level and text, or `texts` keyed by the payload (no key, no flash)."
  defstruct level: :info, text: nil, texts: nil

  defimpl ZeroCoupled.Ports.Step do
    def push(%{texts: nil, level: l, text: t} = s, _), do: {:emit, [ui: {:flash, l, t}], s}

    def push(%{texts: texts, level: l} = s, {_, key}) do
      case Map.fetch(texts, key) do
        {:ok, t} -> {:emit, [ui: {:flash, l, t}], s}
        :error -> {:quiet, s}
      end
    end
  end
end

defmodule ZeroCoupled.Paradigms.ToStore do
  @moduledoc "A sink: a value in, a function called for its effect. Config: the function."
  defstruct [:write]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{write: write} = s, {_, value}),
      do:
        (
          write.(value)
          {:quiet, s}
        )
  end
end

defmodule ZeroCoupled.Paradigms.FromStore do
  @moduledoc "A source: pushed anything, it reads through a function and emits the result on `:loaded`. Config: the read function."
  defstruct [:read]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{read: read} = s, {_, arg}), do: {:emit, [loaded: read.(arg)], s}
  end
end

defmodule ZeroCoupled.Paradigms.Via do
  @moduledoc "A transform: a value in, `fun.(value)` out on `:out`. Config: the function."
  defstruct [:fun]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{fun: fun} = s, {_, value}), do: {:emit, [out: fun.(value)], s}
  end
end

defmodule ZeroCoupled.Paradigms.ToTimer do
  @moduledoc """
  A sink: `{:start, payload}` in starts a clock that will push `{into_input, payload}` into
  `into_instance` after `ms`; `:cancel` stops it. Config: name, ms, into `{instance, input}`.
  """
  defstruct [:name, :ms, :into]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{name: n, ms: ms, into: {inst, input}} = s, {_, {:start, payload}}),
      do: {:emit, [ui: {:timer_start, n, ms, {:feed, inst, {input, payload}}}], s}

    def push(%{name: n} = s, {_, :cancel}), do: {:emit, [ui: {:timer_cancel, n}], s}
  end
end

defmodule ZeroCoupled.Paradigms.ToPatch do
  @moduledoc "A sink: a step in, a URL patch out on `:ui` when the step has a path. Config: paths by step."
  defstruct [:paths]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{paths: paths} = s, {_, step}) do
      case Map.fetch(paths, step) do
        {:ok, path} -> {:emit, [ui: {:patch, path}], s}
        :error -> {:quiet, s}
      end
    end
  end
end

defmodule ZeroCoupled.Paradigms.ToAsync do
  @moduledoc """
  A sink: a value in, `fun.(value)` run off the page, its `{:ok, v}` or `{:error, r}` pushed
  back into the circuit at `ok` or `error` (`{instance, input}`). Config: name, fun, ok, error.
  """
  defstruct [:name, :fun, :ok, :error]

  defimpl ZeroCoupled.Ports.Step do
    def push(%{name: n, fun: fun, ok: ok, error: error} = s, {_, value}) do
      job = fn ->
        try do
          case fun.(value) do
            {:ok, v} -> {:feed, ok, v}
            {:error, r} -> {:feed, error, r}
          end
        catch
          kind, reason -> {:feed, error, {kind, reason}}
        end
      end

      {:emit, [ui: {:async, n, job}], s}
    end
  end
end

defmodule ZeroCoupled.Paradigms.ToRedirect do
  @moduledoc "A sink: a URL in, an external redirect out on `:ui`."
  defstruct []

  defimpl ZeroCoupled.Ports.Step do
    def push(s, {_, url}), do: {:emit, [ui: {:redirect, url}], s}
  end
end
