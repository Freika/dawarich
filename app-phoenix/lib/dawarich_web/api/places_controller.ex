defmodule DawarichWeb.Api.PlacesController do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn, only: [delete_resp_header: 2, merge_resp_headers: 2, register_before_send: 2]

  alias Dawarich.PlacesApi
  alias DawarichWeb.Api.{Body, Respond}

  @impl true
  def init({:closure, action}),
    do: if(Dawarich.Standalone.enabled?(), do: {:closure, action}, else: action)

  def init(action), do: action

  @impl true
  def call(conn, action) when action in [:nearby, :search] do
    module = if action == :nearby, do: Dawarich.PlacesApi.Nearby, else: Dawarich.PlacesApi.Search
    {:ok, status, term} = module.run(conn.assigns.api_user, conn.assigns.api_params)
    Respond.json(conn, status, module.term(term))
  end

  def call(conn, {:closure, action}) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)

    case Dawarich.PlacesApi.Closure.run(action, conn.assigns.api_user, params, DateTime.utc_now()) do
      {:ok, status, term, headers} ->
        conn |> merge_resp_headers(headers) |> Respond.json(status, term)

      :no_content ->
        conn |> register_before_send(&delete_resp_header(&1, "content-type")) |> Respond.head(204)
    end
  end

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
