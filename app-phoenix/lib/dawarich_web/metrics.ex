defmodule DawarichWeb.Metrics do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      not Dawarich.Metrics.enabled?() ->
        conn |> put_resp_content_type("text/plain", nil) |> send_resp(404, "")

      authorized?(conn) ->
        conn
        |> put_resp_content_type("text/plain", nil)
        |> put_resp_header("content-type", "text/plain; version=0.0.4")
        |> send_resp(200, Dawarich.Metrics.Drain.scrape(Dawarich.Metrics.scrape()))

      true ->
        conn
        |> put_resp_content_type("text/plain", nil)
        |> put_resp_header("www-authenticate", ~s(Basic realm="Dawarich Metrics"))
        |> send_resp(401, "Unauthorized")
    end
  end

  defp authorized?(conn) do
    case credentials(conn) do
      {user, password} ->
        valid_user = compare(user, System.get_env("METRICS_USERNAME") || "")
        valid_password = compare(password, System.get_env("METRICS_PASSWORD") || "")
        valid_user and valid_password

      _ ->
        false
    end
  end

  defp credentials(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         [scheme, encoded] <- String.split(header, ~r/\s+/, parts: 2, trim: true),
         true <- String.valid?(scheme),
         true <- String.downcase(scheme) == "basic",
         {:ok, decoded} <- Base.decode64(encoded, ignore: :whitespace),
         [user, password] <- :binary.split(decoded, ":") do
      {user, password}
    else
      _ -> :error
    end
  end

  defp compare(a, b),
    do: Plug.Crypto.secure_compare(:crypto.hash(:sha256, a), :crypto.hash(:sha256, b))
end
