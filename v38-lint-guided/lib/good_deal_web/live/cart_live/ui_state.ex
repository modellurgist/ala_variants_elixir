defmodule GoodDealWeb.CartLive.UIState do
  @moduledoc false

  # undo: nil, or %{item: removed_line, ref: timer_ref}
  defstruct active_tab: :items, promo_error: nil, undo: nil, saved: [], wishlist: []
end
