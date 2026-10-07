defmodule DawarichWeb.RailsCsrf do
  @moduledoc false

  @global "!real_csrf_token"

  def new_token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  def masked_token(session), do: masked(session, @global)

  def masked_form_token(session, action, method),
    do: masked(session, action <> "#" <> String.downcase(method))

  defp masked(%{"_csrf_token" => real}, identifier) when is_binary(real) do
    case decode(real) do
      {:ok, <<raw::binary-size(32)>>} ->
        pad = :crypto.strong_rand_bytes(32)
        Base.url_encode64(pad <> :crypto.exor(pad, hmac(raw, identifier)), padding: false)

      _ ->
        nil
    end
  end

  defp masked(_session, _identifier), do: nil

  def valid?(session, token), do: valid_token?(session, token, @global)

  def valid?(session, token, path, method),
    do:
      valid?(session, token) or
        valid_token?(
          session,
          token,
          String.trim_trailing(path, "/") <> "#" <> String.downcase(method)
        )

  defp valid_token?(%{"_csrf_token" => real}, token, identifier)
       when is_binary(real) and is_binary(token) do
    with {:ok, <<raw::binary-size(32)>>} <- decode(real),
         {:ok, decoded} <- decode(token) do
      case decoded do
        <<unmasked::binary-size(32)>> ->
          Plug.Crypto.secure_compare(unmasked, raw)

        <<pad::binary-size(32), masked::binary-size(32)>> ->
          unmasked = :crypto.exor(pad, masked)

          Plug.Crypto.secure_compare(unmasked, raw) or
            Plug.Crypto.secure_compare(unmasked, hmac(raw, identifier))

        _ ->
          false
      end
    else
      _ -> false
    end
  end

  defp valid_token?(_session, _token, _identifier), do: false

  defp decode(token) do
    encoded = token |> String.replace("-", "+") |> String.replace("_", "/")

    padded =
      if String.ends_with?(encoded, "="),
        do: encoded,
        else: String.pad_trailing(encoded, div(byte_size(encoded) + 3, 4) * 4, "=")

    with {:ok, decoded} <- Base.decode64(padded),
         true <- Base.encode64(decoded) == padded do
      {:ok, decoded}
    else
      _ -> :error
    end
  end

  defp hmac(raw, identifier), do: :crypto.mac(:hmac, :sha256, raw, identifier)
end
