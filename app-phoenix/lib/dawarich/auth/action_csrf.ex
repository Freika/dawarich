defmodule Dawarich.Auth.ActionCsrf do
  @moduledoc false
  alias DawarichWeb.RailsCsrf

  def valid?(session, token, method, path)
      when is_binary(token) and is_binary(method) and is_binary(path) do
    RailsCsrf.valid?(session, token) or per_form?(session, token, method, path)
  rescue
    ArgumentError -> false
  end

  def valid?(_, _, _, _), do: false

  defp per_form?(%{"_csrf_token" => real}, token, method, path) when is_binary(real) do
    with {:ok, <<raw::binary-size(32)>>} <- Base.url_decode64(real, padding: false),
         {:ok, <<pad::binary-size(32), masked::binary-size(32)>> = decoded} <-
           Base.url_decode64(token, padding: false),
         true <- Base.url_encode64(decoded, padding: false) == token do
      action = URI.parse(path).path |> String.trim_trailing("/")
      expected = :crypto.mac(:hmac, :sha256, raw, action <> "#" <> String.downcase(method))
      Plug.Crypto.secure_compare(:crypto.exor(pad, masked), expected)
    else
      _ -> false
    end
  end

  defp per_form?(_, _, _, _), do: false
end
