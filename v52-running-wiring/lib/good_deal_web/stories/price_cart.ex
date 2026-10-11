defmodule GoodDealWeb.Stories.PriceCart do
  @moduledoc """
  The shopper's cart is priced: a shipping choice, a promo code, gift wrap, and checkout starting
  from the total. Its parts are the promo code and the totals, wired to each other here; the lines
  come in on `contents` from whichever story edits them. Out: `:summary`, `:promo_error` (a message
  to show, or nil), `:checkout_started` (the summary, for whoever runs checkout).
  """
  use GoodDealWeb, :html
  import Phoenix.LiveView, only: [put_flash: 3]
  import GoodDeal.Components.Parts

  alias GoodDeal.State.{CartTotals, Promo}
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{promo: Promo, totals: CartTotals}
  def events, do: ~w(select_shipping apply_promo start_checkout)

  def ports,
    do: %{
      in: [contents: :contents],
      out: [summary: :summary, promo_error: :message, checkout_started: :summary]
    }

  @doc "Config: `pricing` (`shipping`, `promo`, `gift_wrap`)."
  def mount(s, opts, _out) do
    pricing = opts[:pricing]
    assign(s, promo: Promo.new(codes: pricing[:promo]), totals: CartTotals.new(pricing: pricing))
  end

  def handle_event("select_shipping", %{"method" => m}, s, out),
    do:
      run(s, :totals, &CartTotals.select_shipping(&1, %{method: String.to_existing_atom(m)}), out)

  def handle_event("apply_promo", %{"code" => code}, s, out),
    do: run(s, :promo, &Promo.enter(&1, %{code: code}), out)

  def handle_event("start_checkout", _params, s, out),
    do: run(s, :totals, &CartTotals.start_checkout(&1, nil), out)

  def input(s, :contents, contents, out),
    do: run(s, :totals, &CartTotals.contents(&1, contents), out)

  defp run(s, part, step, out), do: Steps.run(s, part, step, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :promo, {:discount, discount}, out),
    do: run(s, :totals, &CartTotals.discount(&1, discount), out)

  defp wire(s, :promo, {:applied, _code}, out),
    do: s |> out.({:promo_error, nil}) |> put_flash(:info, "Promo applied!")

  defp wire(s, :promo, {:rejected, _code}, out),
    do:
      s
      |> out.({:promo_error, "Invalid promo code"})
      |> put_flash(:error, "Invalid promo code")

  defp wire(s, :totals, {:summary, summary}, out), do: out.(s, {:summary, summary})

  defp wire(s, :totals, {:checkout_started, summary}, out),
    do: out.(s, {:checkout_started, summary})

  attr :summary, :map, required: true
  attr :promo_error, :string, default: nil
  attr :t, :map, required: true

  def totals(assigns) do
    ~H"""
    <.cart_summary summary={@summary} t={@t} />
    <.shipping_selector
      summary={@summary}
      heading={@t.shipping}
      free_over={@t.free_over}
      event="select_shipping"
    />
    <.promo_form code={@summary.promo_code} error={@promo_error} event="apply_promo" t={@t} />
    <.primary_button event="start_checkout" disabled={@summary.empty?} class="mt-6 w-full">
      {@t.checkout} · {@summary.total}
    </.primary_button>
    """
  end
end
