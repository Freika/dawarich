defmodule DawarichWeb.NativeRequest do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _) do
    conn = conn |> DawarichWeb.NativeM6Envelope.prepare()
    original = conn.method

    conn =
      conn
      |> put_private(:dawarich_native_api, api?(conn))
      |> put_private(:dawarich_method, original)
      |> Plug.Head.call([])

    cond do
      DawarichWeb.NativeM4RetiredWrites.retired?(conn) ->
        DawarichWeb.NativeM4RetiredWrites.refuse(conn)

      true ->
        dispatch(conn, original)
    end
  end

  defp dispatch(conn, original) do
    case Phoenix.Router.route_info(DawarichWeb.Router, conn.method, conn.path_info, conn.host) do
      :error ->
        DawarichWeb.RailsErrors.respond(conn, 404)

      route ->
        if DawarichWeb.RouteConstraints.valid?(route) and
             not (original == "HEAD" and route[:head] == false),
           do: conn,
           else: DawarichWeb.RailsErrors.respond(conn, 404)
    end
  end

  def api?(%{path_info: ["api", "v1" | _]}), do: true
  def api?(_), do: false
end
