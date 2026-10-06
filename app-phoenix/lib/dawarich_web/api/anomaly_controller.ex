defmodule DawarichWeb.Api.AnomalyController do
  @moduledoc false
  @behaviour Plug
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, :create) do
    {_, status, body} =
      Dawarich.Points.ApiAnomaly.reapply(
        Dawarich.Repo,
        conn.assigns.api_user,
        conn.assigns.api_params,
        Dawarich.Imports.Api.context(conn)
      )

    Respond.json(conn, status, body)
  rescue
    _ -> Respond.head(conn, 500)
  end
end
