defmodule GoodDeal.ChannelFixtures do
  @moduledoc """
  A test-owned `%Channel{}` for rule tests: every enforced field gets a neutral value, so a
  new required field changes this one place, and each test overrides the field its rule reads.
  """

  alias GoodDeal.Channel

  def channel_fixture(fields \\ []) do
    struct!(
      Channel,
      [
        name: :test,
        shipping_methods: [],
        default_shipping_method: nil,
        gift_wrap_price: 0,
        low_stock_threshold: 0,
        postal_code_length: [min: 1],
        po_number: %{format: ~r/.+/, message: "is required"}
      ] ++ fields
    )
  end
end
