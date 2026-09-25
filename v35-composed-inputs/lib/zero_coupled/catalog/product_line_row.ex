defmodule ZeroCoupled.Catalog.ProductLineRow do
  @moduledoc """
  Generic, zero-coupled presentation abstraction: a product line — thumbnail,
  name, price — with two open UI-layout ports (`:detail`, `:actions`) the app
  fills. Knows nothing of carts, saved items, wishlists, or any domain feature.

  Data arrives as a **projected port value** — `%{thumbnail, name, amount}`,
  a neutral shape, never a domain struct. The owning feature does the
  `item -> %{thumbnail, name, amount}` projection once, server side, at the
  stream boundary (where touching the domain is allowed); this component only
  reads the port. That is what lets it wire into any product list unchanged
  (the port-vs-prop test) and what keeps it clean under `ComponentPurity`:
  no domain alias, no `@a.b.c` reach, no literal event/hook/id string.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :product, :map, required: true, doc: "%{thumbnail, name, amount}"
  attr :cols, :string, default: "4rem_1fr_auto"
  attr :price_suffix, :string, default: ""
  slot :detail
  slot :actions

  def product_line(assigns) do
    ~H"""
    <div id={@id} class={"grid grid-cols-[#{@cols}] items-center gap-4 border-b py-4"}>
      <img class="w-16 h-16 object-contain" src={@product.thumbnail} alt={@product.name} />
      <div>
        <div class="font-medium"><%= @product.name %></div>
        <div class="text-sm text-zinc-500"><%= Money.new(@product.amount) %><%= @price_suffix %></div>
        <%= render_slot(@detail) %>
      </div>
      <%= render_slot(@actions) %>
    </div>
    """
  end
end
