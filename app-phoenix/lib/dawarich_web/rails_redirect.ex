defmodule DawarichWeb.RailsRedirect do
  @moduledoc false
  import Plug.Conn, only: [get_req_header: 2]

  def back(conn) do
    base = DawarichWeb.RequestURL.base(conn)

    with [value] <- get_req_header(conn, "referer"),
         false <- Regex.match?(~r/[\x00-\x20\\]/, value),
         {:ok, uri} <- URI.new(value),
         origin = URI.parse(base) do
      cond do
        uri.host == origin.host and uri.scheme in ["http", "https"] ->
          value

        uri.host == origin.host and is_nil(uri.scheme) ->
          origin.scheme <> ":" <> value

        is_nil(uri.host) and is_nil(uri.scheme) and String.starts_with?(value, "/") and
            not String.starts_with?(value, "//") ->
          base <> value

        true ->
          base <> "/"
      end
    else
      _ -> base <> "/"
    end
  end
end
