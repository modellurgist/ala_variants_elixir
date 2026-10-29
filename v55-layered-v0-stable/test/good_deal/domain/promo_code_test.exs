defmodule GoodDeal.Domain.PromoCodeTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Channel
  alias GoodDeal.Domain.PromoCode

  @channel %Channel{name: :test, promo_codes: %{"TEN" => 10}}

  test "normalizes by trimming and upcasing" do
    assert PromoCode.normalize("  ten ") == "TEN"
    assert PromoCode.normalize(nil) == ""
  end

  test "a code is valid only as listed" do
    assert PromoCode.valid?(@channel, "TEN")
    refute PromoCode.valid?(@channel, "ten")
  end

  test "discount is the listed percent, labelled with the code" do
    assert PromoCode.discount(@channel, "TEN") == {10, "TEN"}
    assert PromoCode.discount(@channel, "NOPE") == {0, nil}
    assert PromoCode.discount(@channel, nil) == {0, nil}
  end
end
