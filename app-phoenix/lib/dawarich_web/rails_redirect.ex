defmodule DawarichWeb.RailsRedirect do
  @moduledoc false
  import Plug.Conn, only: [get_req_header: 2]
  alias DawarichWeb.RequestURL

  def back(conn, fallback \\ "/") do
    with [value] <- get_req_header(conn, "referer"),
         true <- String.valid?(value),
         false <- Regex.match?(~r/[\\\s\p{Cc}\p{Z}]/u, value),
         false <- String.starts_with?(value, "//"),
         {:ok, uri} <- URI.new(value),
         nil <- uri.userinfo,
         true <-
           uri.host == conn.host or
             (is_nil(uri.host) and is_nil(uri.scheme) and String.starts_with?(value, "/")) do
      absolute(conn, value)
    else
      _ -> absolute(conn, fallback)
    end
  end

  defp absolute(conn, "/" <> _ = path), do: RequestURL.base(conn) <> path
  defp absolute(_conn, url), do: url
end
