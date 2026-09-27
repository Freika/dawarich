defmodule DawarichWeb.RailsCsrf do
  @moduledoc false

  @global "!real_csrf_token"

  def masked_token(%{"_csrf_token" => real}) when is_binary(real) do
    case Base.url_decode64(real, padding: false) do
      {:ok, raw} ->
        pad = :crypto.strong_rand_bytes(32)
        Base.url_encode64(pad <> :crypto.exor(pad, global(raw)), padding: false)

      :error ->
        nil
    end
  end

  def masked_token(_session), do: nil

  def valid?(%{"_csrf_token" => real}, token) when is_binary(real) and is_binary(token) do
    with {:ok, raw} <- Base.url_decode64(real, padding: false),
         {:ok, <<pad::binary-size(32), masked::binary-size(32)>>} <-
           Base.url_decode64(token, padding: false) do
      Plug.Crypto.secure_compare(:crypto.exor(pad, masked), global(raw))
    else
      _ -> false
    end
  end

  def valid?(_session, _token), do: false

  defp global(raw), do: :crypto.mac(:hmac, :sha256, raw, @global)
end
