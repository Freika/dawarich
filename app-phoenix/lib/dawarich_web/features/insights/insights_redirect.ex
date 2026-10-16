defmodule DawarichWeb.InsightsRedirect do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(action), do: action

  def call(%{path_params: %{"year" => year}} = conn, :year) do
    if Regex.match?(~r/\A[0-9]{4}\z/, year),
      do: redirect(conn, Dawarich.RubyInteger.to_i(year)),
      else: conn |> send_resp(404, "") |> halt()
  end

  def call(conn, :index), do: redirect(conn, "all")

  defp redirect(conn, year) do
    conn
    |> put_resp_header("location", "/insights?" <> URI.encode_query(%{"year" => year}))
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
