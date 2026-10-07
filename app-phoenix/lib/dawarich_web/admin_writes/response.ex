defmodule DawarichWeb.AdminWrites.Response do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{RailsHeaders, RailsSession, RequestURL}

  def redirect(conn, status, path, kind, message) do
    flash = %{"discard" => [], "flashes" => %{to_string(kind) => message}}

    location = if String.starts_with?(path, "/"), do: RequestURL.base(conn) <> path, else: path

    conn
    |> RailsSession.stage(%{"flash" => flash})
    |> RailsHeaders.call([])
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("location", location)
    |> put_resp_header("x-dawarich-admin-owner", "native-admin-writes")
    |> send_resp(status, "")
    |> halt()
  end
end
