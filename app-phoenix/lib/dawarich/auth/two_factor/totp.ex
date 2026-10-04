defmodule Dawarich.Auth.TwoFactor.Totp do
  @moduledoc false
  import Bitwise
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.Token
  @alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  def generate_secret(entropy \\ :crypto.strong_rand_bytes(20)),
    do: Base.encode32(entropy, padding: false)

  def decode(secret) when is_binary(secret) do
    {_, _, bytes} =
      secret
      |> String.replace("=", "")
      |> String.upcase(:ascii)
      |> String.to_charlist()
      |> Enum.reduce({0, 0, []}, fn char, {buffer, bits, bytes} ->
        value = Enum.find_index(@alphabet, &(&1 == char))
        if is_nil(value), do: raise(ArgumentError, "invalid Base32 character")
        buffer = buffer <<< 5 ||| value
        bits = bits + 5

        if bits >= 8,
          do: {buffer, bits - 8, [buffer >>> (bits - 8) &&& 255 | bytes]},
          else: {buffer, bits, bytes}
      end)

    bytes |> Enum.reverse() |> :erlang.list_to_binary()
  end

  def at(secret, timestamp), do: code(decode(secret), div(timestamp, 30))

  def verify(secret, input, at, consumed \\ nil)

  def verify(secret, input, at, consumed) when is_binary(secret) and is_binary(input) do
    if Token.blank?(secret) do
      :invalid
    else
      input = String.replace(input, ~r/[\x09-\x0D ]+/, "")
      key = decode(secret)

      div(at - 30, 30)..div(at + 30, 30)
      |> Enum.reduce(:invalid, fn timestep, result ->
        if (is_nil(consumed) or timestep > consumed) and
             Plug.Crypto.secure_compare(input, code(key, timestep)),
           do: {:ok, timestep},
           else: result
      end)
    end
  end

  def verify(_, _, _, _), do: :invalid

  def provisioning_uri(secret, label, issuer \\ "Dawarich") do
    issuer = issuer |> Account.strip() |> String.replace(":", "_")
    label = label |> String.replace(~r/[\x00\x09-\x0D ]+\z/, "") |> String.replace(":", "_")

    "otpauth://totp/#{escape(issuer)}:#{escape(label)}?secret=#{escape(secret)}&issuer=#{escape(issuer)}"
  end

  defp escape(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp code(key, timestep) do
    hmac = :crypto.mac(:hmac, :sha, key, <<timestep::unsigned-big-64>>)
    offset = :binary.last(hmac) &&& 15
    value = :binary.decode_unsigned(binary_part(hmac, offset, 4)) &&& 0x7FFFFFFF
    value |> rem(1_000_000) |> Integer.to_string() |> String.pad_leading(6, "0")
  end
end
