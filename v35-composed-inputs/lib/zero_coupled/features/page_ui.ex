# Page-level UI-only state as its own small feature (V28 kept this in the
# Session struct; V29 makes it a slot like everything else).

defmodule ZeroCoupled.Features.PageUI do
  @moduledoc """
  UI-only page state: the active tab and the promo error message.
  Domain state never lives here; this slot never touches persistence.
  """

  @type tab :: :items | :saved | :wishlist
  @type t :: %__MODULE__{active_tab: tab(), promo_error: String.t() | nil}

  defstruct active_tab: :items, promo_error: nil

  @spec init(keyword()) :: t()
  def init(_opts), do: %__MODULE__{}
end

defmodule ZeroCoupled.Features.PageUI.Intents do
  @moduledoc false
  use ZeroCoupled.Feature.Intents, slot: :ui

  alias ZeroCoupled.Features.PageUI

  # ── Intents ──────────────────────────────────────────────────────────

  intent :switch_tab, params: [tab: :atom]

  def switch_tab(session, %{tab: tab}) when tab in [:items, :saved, :wishlist] do
    {put_slot(session, %{session.ui | active_tab: tab}), []}
  end

  def switch_tab(session, _args), do: {session, []}

  # ── Reactions ────────────────────────────────────────────────────────

  @doc "Reaction to `:promo_rejected`: surface the inline error."
  def set_promo_error(%PageUI{} = ui, %{message: message}) do
    {%{ui | promo_error: message}, []}
  end

  @doc "Reaction to `:promo_applied`: clear any inline error."
  def clear_promo_error(%PageUI{} = ui, _payload) do
    {%{ui | promo_error: nil}, []}
  end
end
