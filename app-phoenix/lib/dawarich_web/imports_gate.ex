defmodule DawarichWeb.ImportsGate do
  @moduledoc false

  alias Dawarich.Imports.UiRecords

  def native?(conn, %{"id" => id}) do
    with %{id: user_id} <- DawarichWeb.RailsAuth.call(conn, []).assigns.current_user,
         {:ok, record} <- UiRecords.get(DawarichWeb.ImportsContext.repo(), user_id, id) do
      record.source == 4
    else
      _ -> false
    end
  end
end
