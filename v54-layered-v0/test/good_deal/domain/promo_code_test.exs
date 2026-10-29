defmodule GoodDeal.Domain.PromoCodeTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.PromoCode

  @codes %{"TEN" => 10}

  test "normalizes by trimming and upcasing" do
    assert PromoCode.normalize("  ten ") == "TEN"
    assert PromoCode.normalize(nil) == ""
  end

  test "a code is valid only as listed" do
    assert PromoCode.valid?(@codes, "TEN")
    refute PromoCode.valid?(@codes, "ten")
  end

  test "discount is the listed percent, labelled with the code" do
    assert PromoCode.discount(@codes, "TEN") == {10, "TEN"}
    assert PromoCode.discount(@codes, "NOPE") == {0, nil}
    assert PromoCode.discount(@codes, nil) == {0, nil}
  end
end
