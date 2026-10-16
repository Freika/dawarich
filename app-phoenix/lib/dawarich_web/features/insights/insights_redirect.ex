defmodule DawarichWeb.InsightsRedirect do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(action), do: action

  def call(conn, action) do
    year =
      if action == :year, do: Dawarich.RubyInteger.to_i(conn.path_params["year"]), else: "all"

    conn
    |> put_resp_header("location", "/insights?" <> URI.encode_query(%{"year" => year}))
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
