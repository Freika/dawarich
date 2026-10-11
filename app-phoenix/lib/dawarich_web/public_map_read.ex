defmodule DawarichWeb.PublicMapRead do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Maps.Dependencies.Public
  alias DawarichWeb.{RailsAuth, SharedLinkCookie}
  alias DawarichWeb.Api.Respond

  def init(action), do: action

  def call(conn, action) do
    conn = conn |> Respond.prepare() |> fetch_query_params()

    conn =
      register_before_send(conn, fn response ->
        response
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("vary", "Cookie")
      end)

    cond do
      (conn.private[:dawarich_method] || conn.method) not in ["GET", "HEAD"] ->
        Respond.json(conn, 405, %{error: "read_only"})

      not same_origin?(conn) ->
        Respond.json(conn, 403, %{error: "origin_refused"})

      Map.has_key?(conn.query_params, "api_key") ->
        Respond.json(conn, 400, %{error: "credential_refused"})

      true ->
        read(conn, action)
    end
  rescue
    _ -> conn |> Respond.prepare() |> Respond.json(503, %{error: "read_unavailable"})
  end

  defp read(conn, action) do
    conn = RailsAuth.call(conn, [])
    user = conn.assigns[:current_user]

    capability = %{
      id: conn.path_params["id"],
      proof: SharedLinkCookie.proofs(conn)[conn.path_params["id"]],
      viewer_scope: user && Dawarich.Maps.principal(user, conn.assigns[:locale] || "en")
    }

    conn =
      conn
      |> assign(:current_user, nil)
      |> assign(:rails_session, %{})
      |> put_private(:dawarich_rails_user, nil)

    params =
      Map.take(conn.query_params, ["source"]) |> Map.put("photo_id", conn.path_params["photo_id"])

    result =
      if action == :metadata,
        do: Public.config(capability),
        else: Public.read(capability, action, params)

    case result do
      {:ok, {:image, body}} ->
        Respond.data(conn, body, "image/jpeg", [])

      {:ok, photos} when action == :photos ->
        Respond.json(
          conn,
          200,
          Enum.map(photos, fn {:object, fields} ->
            Map.new(fields) |> Map.take(~w(id latitude longitude source taken_at))
          end)
        )

      {:ok, data} ->
        Respond.json(conn, 200, data)

      {:error, reason} ->
        Respond.json(conn, status(reason), %{error: Atom.to_string(reason)})
    end
  end

  defp status(:locked), do: 401
  defp status(:changed), do: 409
  defp status(:unavailable), do: 503
  defp status(_), do: 404

  defp same_origin?(conn) do
    get_req_header(conn, "sec-fetch-site") in [[], ["same-origin"], ["none"]] and
      get_req_header(conn, "origin") in [
        [],
        [URI.to_string(%URI{scheme: to_string(conn.scheme), host: conn.host, port: conn.port})]
      ]
  end
end
