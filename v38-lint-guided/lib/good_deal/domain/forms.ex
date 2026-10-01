defmodule GoodDeal.Domain.Forms do
  @moduledoc "The two forms a shopper fills in, validated as embedded schemas: a shipping address and a purchase order."

  defmodule Address do
    @moduledoc false
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

  defmodule PurchaseOrder do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :number, :string
      field :notes, :string
    end

    def changeset(po, params) do
      po
      |> cast(params, [:number, :notes])
      |> validate_required([:number])
      |> validate_format(:number, ~r/^PO-\d{4,}$/, message: "must look like PO-1234")
    end
  end
end
