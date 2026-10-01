defmodule ZeroCoupled.Features.Checkout do
  @moduledoc """
  Where the shopper is in paying: a step machine over a flow table the page supplies, plus the
  address they enter. Ports out:

    * `:step`      the step now showing
    * `:form`      the address changeset to render (after validation or a failed submit)
    * `:address`   the address once accepted
    * `:blocked`   why paying can't start: `:empty` or `:out_of_stock`
    * `:payment`   `{line_items, cart_id}`: a payment to start, somewhere else
    * `:done`      the URL to send the shopper to once paid

  The table, the starting step, which URL jumps are allowed, and where stock levels come from
  are all configuration.
  """
  alias ZeroCoupled.Cart
  alias ZeroCoupled.Paradigms.Transitions

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
    def changeset(address, params) do
      address
      |> cast(params, @fields)
      |> validate_required(@fields)
      |> validate_format(:postal_code, ~r/^\d{4,10}$/, message: "must be 4–10 digits")
    end
  end

  defstruct step: nil, start: nil, flow: [], url_edges: [], address: nil, stock_levels: nil

  def ports,
    do: %{
      in: [
        start: :summary,
        validate: :params,
        submit_address: :params,
        edit_address: :event,
        pay: :cart,
        succeeded: :url,
        failed: :reason,
        goto: :step
      ],
      out: [
        step: :step,
        form: :changeset,
        address: :address,
        blocked: :reason,
        payment: :payment,
        done: :url
      ]
    }

  def new(opts) do
    %__MODULE__{
      flow: Keyword.fetch!(opts, :flow),
      start: Keyword.fetch!(opts, :start),
      step: Keyword.fetch!(opts, :start),
      url_edges: Keyword.get(opts, :url_edges, []),
      address: %Address{},
      stock_levels: Keyword.fetch!(opts, :stock_levels)
    }
  end

  def address_form(%__MODULE__{address: address}, params \\ %{}),
    do: Address.changeset(address, params)

  @doc "Begin, given the cart's summary: an empty cart can't check out."
  def start(%__MODULE__{} = c, %{empty?: true}), do: {c, [blocked: :empty]}

  def start(%__MODULE__{} = c, _summary),
    do: {%{c | step: c.start}, [step: c.start, form: address_form(c)]}

  @doc "Live validation of the address form: no step change, just the changeset to show."
  def validate(%__MODULE__{} = c, params), do: {c, [form: address_form(c, params)]}

  def submit_address(%__MODULE__{} = c, params) do
    changeset = address_form(c, params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, address} ->
        {c, outs} = advance(%{c | address: address}, :submit_address)
        {c, [address: address] ++ outs}

      {:error, changeset} ->
        {c, [form: changeset]}
    end
  end

  def edit_address(%__MODULE__{} = c, _), do: advance(c, :edit_address)

  @doc "Pay for the cart, after asking the configured stock source for fresh levels."
  def pay(%__MODULE__{} = c, %Cart{} = cart) do
    case Cart.check_ready(cart, c.stock_levels.(Enum.map(cart.items, & &1.product.id))) do
      :ok ->
        {c, outs} = advance(c, :pay)
        {c, outs ++ [payment: {Cart.line_items(cart), cart.cart_id}]}

      {:error, :empty_cart} ->
        {c, [blocked: :empty]}

      {:error, :out_of_stock} ->
        {c, [blocked: :out_of_stock]}
    end
  end

  def succeeded(%__MODULE__{} = c, url),
    do: {%{c | step: :complete}, [step: :complete, done: url]}

  def failed(%__MODULE__{} = c, _reason), do: {%{c | step: :error}, [step: :error]}

  @doc "The URL asked for a step: honour it only along an allowed jump."
  def goto(%__MODULE__{} = c, step) do
    if {c.step, step} in c.url_edges, do: {%{c | step: step}, [step: step]}, else: {c, []}
  end

  defp advance(c, event) do
    case Transitions.step(c.flow, c.step, event) do
      {:moved, to} -> {%{c | step: to}, [step: to]}
      {:stayed, _} -> {c, []}
    end
  end
end
