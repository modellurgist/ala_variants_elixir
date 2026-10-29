defmodule GoodDeal.State.Checkout do
  @moduledoc """
  Where the shopper is in paying: a step machine over a flow table the page supplies, plus the
  address they enter. Each move answers the checkout in its new step (`step` is the one to show);
  a move that can't happen answers why: a changeset to show, or `{:blocked, :empty | :out_of_stock}`.
  The table, the starting step, which URL jumps are allowed, and where stock levels come from
  are all configuration, as are the `line_items` builder and the form's `messages`
  (`%{postal_code: text}`).
  """
  alias GoodDeal.Domain.{BuildLineItems, CheckStock, ValidateCheckout}
  alias GoodDeal.Paradigms.Transitions

  defmodule Address do
    @moduledoc "The shipping address, validated as an embedded schema."
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :name, :string
      field :line1, :string
      field :city, :string
      field :postal_code, :string
    end

    @fields [:name, :line1, :city, :postal_code]
    def changeset(address, params, messages) do
      address
      |> cast(params, @fields)
      |> validate_required(@fields)
      |> validate_format(:postal_code, ~r/^\d{4,10}$/, message: messages.postal_code)
    end
  end

  defstruct step: nil,
            start: nil,
            flow: [],
            url_edges: [],
            address: nil,
            stock_levels: nil,
            line_items: nil,
            messages: %{}

  def new(opts) do
    %__MODULE__{
      flow: Keyword.fetch!(opts, :flow),
      start: Keyword.fetch!(opts, :start),
      step: Keyword.fetch!(opts, :start),
      url_edges: Keyword.get(opts, :url_edges, []),
      address: %Address{},
      stock_levels: Keyword.fetch!(opts, :stock_levels),
      line_items: Keyword.fetch!(opts, :line_items),
      messages: Keyword.fetch!(opts, :messages)
    }
  end

  @doc "The address form as it stands, or with `params` typed into it."
  def address_form(%__MODULE__{address: address} = c, params \\ %{}),
    do: Address.changeset(address, params, c.messages)

  @doc "Begin, given the cart's summary: an empty cart can't check out."
  def start(%__MODULE__{}, %{empty?: true}), do: {:blocked, :empty}
  def start(%__MODULE__{} = c, _summary), do: {:ok, %{c | step: c.start}}

  def submit_address(%__MODULE__{} = c, params) do
    case Ecto.Changeset.apply_action(address_form(c, params), :insert) do
      {:ok, address} ->
        {:ok, %{c | address: address, step: Transitions.next(c.flow, c.step, :submit_address)}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def edit_address(%__MODULE__{} = c),
    do: %{c | step: Transitions.next(c.flow, c.step, :edit_address)}

  @doc """
  Pay for a cart's stored lines, `{cart_id, items}`, after asking the configured stock source for
  fresh levels: `{:ok, checkout, {line_items, cart_id}}`, the payment to charge. Checkout gets the
  lines and the id, not the cart.
  """
  def pay(%__MODULE__{} = c, {cart_id, items}) do
    case ready(items, c.stock_levels.(Enum.map(items, & &1.product.id))) do
      :ok ->
        {:ok, %{c | step: Transitions.next(c.flow, c.step, :pay)},
         {BuildLineItems.call(c.line_items, items), cart_id}}

      {:error, :empty_cart} ->
        {:blocked, :empty}

      {:error, :out_of_stock} ->
        {:blocked, :out_of_stock}
    end
  end

  def succeeded(%__MODULE__{} = c), do: %{c | step: :complete}
  def failed(%__MODULE__{} = c), do: %{c | step: :error}

  @doc "The URL asked for a step: honour it only along an allowed jump."
  def goto(%__MODULE__{} = c, step), do: %{c | step: Transitions.jump(c.url_edges, c.step, step)}

  # paying needs a non-empty cart whose lines are all in stock
  defp ready(items, stock_levels) do
    with {:ok, items} <- ValidateCheckout.call(items), do: CheckStock.call(items, stock_levels)
  end
end
