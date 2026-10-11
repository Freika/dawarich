defmodule DawarichWeb.BrowserMapAreas do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Areas.Api
  alias DawarichWeb.Api.Respond

  def call(conn) do
    case Api.index(Dawarich.Repo, conn.assigns.api_user, Dawarich.Settings.Api.context(conn)) do
      {:ok, 200, rows} ->
        params = conn.assigns.api_params
        page = String.to_integer(params["page"])
        per = String.to_integer(params["per_page"])
        conn = put_resp_header(conn, "x-total-pages", to_string(ceil(length(rows) / per)))
        Respond.json(conn, 200, Enum.slice(rows, (page - 1) * per, per))

      {_, status, body} ->
        Respond.json(conn, status, body)
    end
  end
end
