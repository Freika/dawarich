defmodule DawarichWeb.Api.SpatialController do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.MapApi.{Countries, TrackedMonths, Cache}
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, :borders) do
    case Countries.borders() do
      {:ok, bytes} ->
        conn
        |> register_before_send(fn conn ->
          conn
          |> delete_resp_header("content-disposition")
          |> delete_resp_header("content-transfer-encoding")
        end)
        |> Respond.data(bytes, "application/json; charset=utf-8", [])

      {:error, status, message} ->
        error(conn, status, message)
    end
  end

  def call(conn, :visited) do
    case Countries.visited(conn.assigns.api_user, conn.assigns.api_params) do
      {:ok, result, etag} ->
        if Cache.fresh?(get_req_header(conn, "if-none-match"), etag, nil, nil),
          do: Respond.not_modified(conn, [{"etag", etag}]),
          else: Respond.json(conn, 200, result, validators: [{"etag", etag}])

      {:error, status, message} ->
        error(conn, status, message)
    end
  end

  def call(conn, :tracked_months),
    do: Respond.json(conn, 200, TrackedMonths.term(TrackedMonths.fetch(conn.assigns.api_user)))

  defp error(conn, status, message),
    do: Respond.json(conn, status, {:object, [{"error", message}]})
end
