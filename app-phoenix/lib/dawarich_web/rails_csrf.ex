defmodule DawarichWeb.RailsCsrf do
  @moduledoc false

  @global "!real_csrf_token"

  def new_token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  def masked_token(session), do: masked(session, @global)

  def masked_form_token(session, action, method),
    do: masked(session, action <> "#" <> String.downcase(method))

  defp masked(%{"_csrf_token" => real}, identifier) when is_binary(real) do
    case Base.url_decode64(real, padding: false) do
      {:ok, raw} ->
        pad = :crypto.strong_rand_bytes(32)
        token = :crypto.mac(:hmac, :sha256, raw, identifier)
        Base.url_encode64(pad <> :crypto.exor(pad, token), padding: false)

      :error ->
        nil
    end
  end

  defp masked(_session, _identifier), do: nil

  def valid?(%{"_csrf_token" => real}, token) when is_binary(real) and is_binary(token) do
    with {:ok, raw} <- Base.url_decode64(real, padding: false),
         {:ok, <<pad::binary-size(32), masked::binary-size(32)>> = decoded} <-
           Base.url_decode64(token, padding: false),
         true <- Base.url_encode64(decoded, padding: false) == token do
      Plug.Crypto.secure_compare(:crypto.exor(pad, masked), global(raw))
    else
      _ -> false
    end
  end

  def valid?(_session, _token), do: false

  defp global(raw), do: :crypto.mac(:hmac, :sha256, raw, @global)
end
