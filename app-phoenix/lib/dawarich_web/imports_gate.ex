defmodule DawarichWeb.ImportsGate do
  @moduledoc false

  alias Dawarich.Imports.UiRecords

  def native?(conn, %{"id" => id}) do
    with %{id: user_id} <- DawarichWeb.RailsAuth.call(conn, []).assigns.current_user,
         {:ok, record} <- UiRecords.get(DawarichWeb.ImportsContext.repo(), user_id, id) do
      admitted?(record)
    else
      _ -> false
    end
  end

  def admitted?(record),
    do:
      (is_nil(record.source) or record.source in 0..15) and record.status in 0..4 and
        (is_nil(record.raw_data) or is_map(record.raw_data)) and
        (is_nil(record.additional_data_extraction) or is_map(record.additional_data_extraction))
end
