defmodule DawarichWeb.Api.PlacesController do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn, only: [delete_resp_header: 2, merge_resp_headers: 2, register_before_send: 2]

  alias Dawarich.PlacesApi
  alias DawarichWeb.Api.{Body, Respond}

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)

    case PlacesApi.run(action, conn.assigns.api_user, params, DateTime.utc_now()) do
      {:ok, status, term, headers} ->
        conn |> merge_resp_headers(headers) |> Respond.json(status, term)

      :no_content ->
        conn
        |> register_before_send(&delete_resp_header(&1, "content-type"))
        |> Respond.head(204)

      {:replay, reason} ->
        Body.replay(conn, reason)
    end
  end
end
