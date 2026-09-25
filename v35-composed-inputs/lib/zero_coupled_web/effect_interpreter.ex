defmodule ZeroCoupledWeb.EffectInterpreter do
  @moduledoc """
  The one place effect *data* meets Phoenix. Extracted from V28's shell
  so every page shares a single interpreter; the page supplies
  page-specific configuration (payment gateway, checkout URLs) via
  `opts` — see the page's `effect_opts/0`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias ZeroCoupled.Effects
  alias ZeroCoupled.Foundation.{Carts, Orders, Products, Broadcast}

  @spec apply_all(Phoenix.LiveView.Socket.t(), [Effects.t()], keyword()) ::
          Phoenix.LiveView.Socket.t()
  def apply_all(socket, effects, opts \\ []) do
    Enum.reduce(effects, socket, &apply_effect(&2, &1, opts))
  end

  defp apply_effect(socket, %Effects.Flash{level: level, message: msg}, _opts),
    do: put_flash(socket, level, msg)

  defp apply_effect(socket, %Effects.Push{event: event, payload: payload}, _opts),
    do: push_event(socket, event, payload)

  defp apply_effect(socket, %Effects.StreamInsert{name: name, item: item, at: at}, _opts),
    do: stream_insert(socket, name, item, at: at)

  defp apply_effect(socket, %Effects.StreamDelete{name: name, item: item}, _opts),
    do: stream_delete(socket, name, item)

  defp apply_effect(socket, %Effects.StreamReset{name: name, items: items}, _opts),
    do: stream(socket, name, items, reset: true)

  defp apply_effect(socket, %Effects.Patch{to: to}, _opts), do: push_patch(socket, to: to)

  # The page supplies its generated flow_path/2 via opts; a step with no
  # declared URL is a silent no-op.
  defp apply_effect(socket, %Effects.PatchFlow{flow: flow, step: step}, opts) do
    case Keyword.fetch!(opts, :flow_path).(flow, step) do
      nil -> socket
      path -> push_patch(socket, to: path)
    end
  end
  defp apply_effect(socket, %Effects.Navigate{to: to}, _opts), do: push_navigate(socket, to: to)

  defp apply_effect(socket, %Effects.Redirect{external: url}, _opts) when is_binary(url),
    do: redirect(socket, external: url)

  defp apply_effect(socket, %Effects.Persist{op: :update_quantity} = p, _opts) do
    Carts.update_quantity(p.cart_id, p.item_id, p.quantity)
    socket
  end

  defp apply_effect(socket, %Effects.Persist{op: :remove} = p, _opts) do
    Carts.remove_item(p.cart_id, p.item_id)
    socket
  end

  defp apply_effect(socket, %Effects.FinalizeOrder{cart_id: cart_id}, _opts) do
    Orders.create(cart_id)

    cart_id
    |> Carts.list_items()
    |> Enum.each(fn item ->
      case Products.decrement_stock(item.product.id, item.quantity) do
        {:ok, product} -> Broadcast.stock_changed(item.product.id, product.stock)
        {:error, _} -> :ok
      end
    end)

    socket
  end

  defp apply_effect(socket, %Effects.StartCheckout{line_items: line_items, metadata: meta}, opts) do
    gateway = Keyword.fetch!(opts, :payment_gateway)
    urls = Keyword.fetch!(opts, :checkout_urls)

    start_async(socket, :checkout, fn ->
      gateway.create_checkout_session(line_items, meta, urls)
    end)
  end

  defp apply_effect(socket, %Effects.StartTimer{name: name, after_ms: ms, message: msg}, _opts) do
    socket = cancel(socket, name)
    ref = Process.send_after(self(), msg, ms)
    assign(socket, :timers, Map.put(timers(socket), name, ref))
  end

  defp apply_effect(socket, %Effects.CancelTimer{name: name}, _opts), do: cancel(socket, name)

  defp cancel(socket, name) do
    case timers(socket) do
      %{^name => ref} when is_reference(ref) ->
        Process.cancel_timer(ref)
        assign(socket, :timers, Map.delete(timers(socket), name))

      _ ->
        socket
    end
  end

  defp timers(socket), do: socket.assigns[:timers] || %{}
end
