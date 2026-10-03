defmodule GoodDeal.State.RecordEdit do
  @moduledoc """
  A record being created or edited through a form: which record, whether it's new, and the changeset
  to show. The changeset function is configuration, so it serves any record a store validates. Ports
  out:

    * `:form`    the changeset to render (on opening, while typing, or after a failed save)
    * `:submit`  `{action, record, params}`, for whatever saves it
    * `:saved`   `{action, record}` once the save succeeded
  """
  defstruct [:changeset, :record, action: :new]

  def ports,
    do: %{
      in: [
        create: :record,
        edit: :record,
        validate: :params,
        submit: :params,
        saved: :save_result
      ],
      out: [form: :changeset, submit: :save_request, saved: :action_record]
    }

  @doc "Config: `changeset`, a function of a record and params."
  def new(opts), do: %__MODULE__{changeset: Keyword.fetch!(opts, :changeset)}

  @doc "Open a new record (`create`) or a stored one (`edit`)."
  def create(%__MODULE__{} = edit, record), do: open(edit, :new, record)
  def edit(%__MODULE__{} = edit, record), do: open(edit, :edit, record)

  def validate(%__MODULE__{} = edit, params),
    do: {edit, [form: %{edit.changeset.(edit.record, params) | action: :validate}]}

  def submit(%__MODULE__{} = edit, params),
    do: {edit, [submit: {edit.action, edit.record, params}]}

  def saved(%__MODULE__{} = edit, {:ok, record}),
    do: {%{edit | record: record}, [saved: {edit.action, record}]}

  def saved(%__MODULE__{} = edit, {:error, changeset}), do: {edit, [form: changeset]}

  defp open(edit, action, record),
    do: {%{edit | action: action, record: record}, [form: edit.changeset.(record, %{})]}
end
