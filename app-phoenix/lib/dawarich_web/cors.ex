defmodule DawarichWeb.Cors do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  @resource "/api/v1/imports/pending"
  @production Mix.env() == :prod

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = List.first(get_req_header(conn, "origin"))
    method = List.first(get_req_header(conn, "access-control-request-method"))

    if (conn.method == "OPTIONS" and origin) && method do
      headers =
        if resource?(conn) and allowed_origin?(origin, @production) and
             String.downcase(method) in ["post", "options"] do
          headers(origin) ++ requested_headers(conn)
        else
          []
        end

      conn |> merge_resp_headers(headers) |> send_resp(200, "") |> halt()
    else
      if resource?(conn) do
        register_before_send(conn, fn conn ->
          conn =
            if allowed_origin?(origin, @production),
              do: merge_resp_headers(conn, headers(origin)),
              else: conn

          vary = get_resp_header(conn, "vary") |> Enum.flat_map(&String.split(&1, ~r/,\s*/))
          put_resp_header(conn, "vary", Enum.join(Enum.uniq(vary ++ ["Origin"]), ", "))
        end)
      else
        conn
      end
    end
  end

  def allowed_origin?(origin, production) when is_binary(origin) do
    origin == "https://dawarich.app" or
      Regex.match?(~r/\Ahttps:\/\/[a-z0-9-]+\.dawarich\.pages\.dev\z/, origin) or
      (not production and Regex.match?(~r/\Ahttp:\/\/localhost(?::\d+)?\z/, origin))
  end

  def allowed_origin?(_origin, _production), do: false

  defp resource?(conn), do: conn.request_path |> URI.decode() |> Path.expand("/") == @resource

  defp headers(origin) do
    [
      {"access-control-allow-origin", origin},
      {"access-control-allow-methods", "POST, OPTIONS"},
      {"access-control-expose-headers", ""},
      {"access-control-max-age", "7200"}
    ]
  end

  defp requested_headers(conn) do
    case get_req_header(conn, "access-control-request-headers") do
      [value] -> [{"access-control-allow-headers", value}]
      _ -> []
    end
  end
end
