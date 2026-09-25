# The multi-step checkout feature: one deletable file (no Components —
# its whole rendering surface is the CheckoutView ActionView).

defmodule ZeroCoupled.Features.CheckoutFlow do
  @moduledoc """
  The checkout flow as a small pure state machine:
  `:address → :payment → :processing → :complete` (or `:error`).
  The address sub-step validates with an Ecto **embedded** schema — a
  pure in-memory changeset, so the whole flow is unit-testable with
  plain ExUnit. (Ecto here is the platform, not a peer.)
  """

  defmodule Address do
    @moduledoc "Embedded schema for the shipping address sub-form."
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{}

    @primary_key false
    embedded_schema do
      field :name, :string
      field :line1, :string
      field :city, :string
      field :postal_code, :string
    end

    @fields [:name, :line1, :city, :postal_code]

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(address, params) do
      address
      |> cast(params, @fields)
      |> validate_required(@fields)
      |> validate_format(:postal_code, ~r/^\d{4,10}$/, message: "must be 4–10 digits")
    end
  end

  @type step :: :address | :payment | :processing | :complete | :error
  @type t :: %__MODULE__{step: step(), address: Address.t() | nil, url: String.t() | nil}

  defstruct step: :address, address: nil, url: nil

  @spec init(keyword()) :: t()
  def init(_opts), do: %__MODULE__{}

  @doc "Changeset for rendering / live-validating the address form."
  @spec address_changeset(t(), map()) :: Ecto.Changeset.t()
  def address_changeset(%__MODULE__{address: address}, params \\ %{}) do
    Address.changeset(address || %Address{}, params)
  end

  @doc "Validate and store the address, advancing to the payment step."
  @spec submit_address(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def submit_address(%__MODULE__{} = checkout, params) do
    changeset = Address.changeset(checkout.address || %Address{}, params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, address} -> {:ok, %{checkout | address: address, step: :payment}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec back_to_address(t()) :: t()
  def back_to_address(%__MODULE__{} = checkout), do: %{checkout | step: :address}

  @spec start_processing(t()) :: t()
  def start_processing(%__MODULE__{} = checkout), do: %{checkout | step: :processing}

  @spec complete(t(), String.t()) :: t()
  def complete(%__MODULE__{} = checkout, url), do: %{checkout | step: :complete, url: url}

  @spec fail(t()) :: t()
  def fail(%__MODULE__{} = checkout), do: %{checkout | step: :error}

  @spec reset(t()) :: t()
  def reset(%__MODULE__{}), do: %__MODULE__{}
end

defmodule ZeroCoupled.Features.CheckoutFlow.Intents do
  @moduledoc """
  Intents owned by the `:checkout` slot. Several are *irregular*
  (dispatched by hand-written page clauses): the address form returns a
  changeset on invalid input, and `pay` needs stock levels fetched by
  the shell.
  """
  use ZeroCoupled.Feature.Intents, slot: :checkout

  alias ZeroCoupled.{Cart, Effects}
  alias ZeroCoupled.Features.CheckoutFlow

  # ── Intents ──────────────────────────────────────────────────────────

  intent :start_checkout

  def start_checkout(session, _args) do
    if Cart.empty?(session.cart) do
      {session, [Effects.flash(:error, "Your cart is empty")]}
    else
      {put_slot(session, CheckoutFlow.reset(session.checkout)),
       [Effects.patch("/cart/checkout")]}
    end
  end

  intent :edit_address

  def edit_address(session, _args) do
    {put_slot(session, CheckoutFlow.back_to_address(session.checkout)),
     [Effects.patch("/cart/checkout")]}
  end

  @doc "Live-validate the address form (no state transition). Irregular helper."
  def change_address(session, params),
    do: CheckoutFlow.address_changeset(session.checkout, params)

  @doc "Irregular: submit the address; advances or returns an errored changeset."
  def submit_address(session, params) do
    case CheckoutFlow.submit_address(session.checkout, params) do
      {:ok, checkout} ->
        {:ok, put_slot(session, checkout), [Effects.patch("/cart/checkout/payment")]}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc "Irregular: pay — validate stock (fetched by the shell), then hand off to async payment."
  def pay(session, stock_levels) do
    case Cart.check_ready(session.cart, stock_levels) do
      :ok ->
        {put_slot(session, CheckoutFlow.start_processing(session.checkout)),
         [
           Effects.start_checkout(Cart.line_items(session.cart), %{
             "cart_id" => session.cart.cart_id
           }),
           Effects.flash(:info, "Processing payment…")
         ]}

      {:error, :empty_cart} ->
        {session, [Effects.flash(:error, "Your cart is empty")]}

      {:error, :out_of_stock} ->
        {session, [Effects.flash(:error, "Some items are out of stock")]}
    end
  end

  @doc "Irregular: async payment finished successfully."
  def checkout_succeeded(session, url) do
    {put_slot(session, CheckoutFlow.complete(session.checkout, url)),
     [Effects.redirect_external(url)]}
  end

  @doc "Irregular: async payment failed."
  def checkout_failed(session, _reason \\ nil) do
    {put_slot(session, CheckoutFlow.fail(session.checkout)),
     [Effects.flash(:error, "Payment failed. Please try again.")]}
  end
end
