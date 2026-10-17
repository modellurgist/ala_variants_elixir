defmodule GoodDeal.Components.ProductLineRow do
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

  # literal class names, so Tailwind's scan of the source finds them; below `sm` the actions wrap
  # to their own line
  @grids %{
    "4rem_1fr_auto" => "grid-cols-[4rem_1fr] sm:grid-cols-[4rem_1fr_auto]",
    "4rem_1fr_auto_auto" => "grid-cols-[4rem_1fr] sm:grid-cols-[4rem_1fr_auto_auto]"
  }

  def product_line(assigns) do
    assigns = assign(assigns, :grid, Map.fetch!(@grids, assigns.cols))

    ~H"""
    <div
      id={@id}
      class={["grid items-center gap-4 border-b border-stone-200 py-5 last:border-b-0", @grid]}
    >
      <img
        class="h-16 w-16 rounded-lg object-cover ring-1 ring-stone-200"
        src={@product.thumbnail}
        alt={@product.name}
      />
      <div class="min-w-0">
        <div class="truncate font-medium text-stone-900">{@product.name}</div>
        <div class="text-sm text-stone-500">{Money.new(@product.amount)}{@price_suffix}</div>
        {render_slot(@detail)}
      </div>
      <div class="col-span-2 flex items-center justify-end gap-4 sm:col-span-1 sm:contents">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end
end
