# ══════════════════════════════════════════════════════════════════════
# GENERATED FILE — do not edit.
# Source of truth: the `flows/0` channel of ZeroCoupledWeb.CartPage.Manifest, ZeroCoupledWeb.PortalPage.Manifest
# (change a manifest first, then run `mix zc.gen`).
# ══════════════════════════════════════════════════════════════════════
defmodule ZeroCoupled.Flows do
  @moduledoc "Merged UI-event flow tables from every page manifest — the one\nneutral module features may consult for their own flow's\ntransitions. Pure data; no web knowledge.\n"
  def initial(:checkout) do
    :address
  end

  def initial(:bulk_order) do
    :lines
  end

  def initial(flow) do
    raise ArgumentError, "unknown flow #{inspect(flow)}"
  end

  def advance(:checkout, :address, :submit_address) do
    :payment
  end

  def advance(:checkout, :payment, :edit_address) do
    :address
  end

  def advance(:checkout, :payment, :pay) do
    :processing
  end

  def advance(:checkout, :error, :pay) do
    :processing
  end

  def advance(:bulk_order, :lines, :go_review) do
    :review
  end

  def advance(:bulk_order, :review, :edit_lines) do
    :lines
  end

  def advance(:bulk_order, :review, :submit_order) do
    :submitted
  end

  def advance(:checkout, _from, _event) do
    :no_transition
  end

  def advance(:bulk_order, _from, _event) do
    :no_transition
  end

  def advance(flow, _from, _event) do
    raise ArgumentError, "unknown flow #{inspect(flow)}"
  end

  def steps(:checkout) do
    [:address, :payment, :processing, :error]
  end

  def steps(:bulk_order) do
    [:lines, :review, :submitted]
  end

  def steps(flow) do
    raise ArgumentError, "unknown flow #{inspect(flow)}"
  end
end
