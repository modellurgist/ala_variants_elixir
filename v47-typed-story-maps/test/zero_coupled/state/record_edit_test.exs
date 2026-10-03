defmodule ZeroCoupled.State.RecordEditTest do
  use ExUnit.Case, async: true
  alias ZeroCoupled.State.RecordEdit

  defp changeset(record, params), do: %{record: record, params: params, action: nil}

  test "a new record opens, validates, submits, and reports what was saved" do
    edit = RecordEdit.new(changeset: &changeset/2)
    {edit, [form: %{record: :blank}]} = RecordEdit.create(edit, :blank)

    assert {_, [form: %{params: %{"a" => 1}, action: :validate}]} =
             RecordEdit.validate(edit, %{"a" => 1})

    assert {_, [submit: {:new, :blank, %{"a" => 1}}]} = RecordEdit.submit(edit, %{"a" => 1})

    assert {_, [saved: :stored, row: {:changed, :stored}, closed: :new]} =
             RecordEdit.saved(edit, {:ok, :stored})
  end

  test "a failed save shows the changeset again" do
    {edit, _} = RecordEdit.new(changeset: &changeset/2) |> RecordEdit.edit(:stored)
    assert {_, [form: :bad]} = RecordEdit.saved(edit, {:error, :bad})
  end
end
