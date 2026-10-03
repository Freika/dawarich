defmodule Dawarich.Auth.Recovery.Token do
  @moduledoc "Column-bound Devise recovery tokens; raw values belong only to delivery intents."
  @columns [:reset_password_token, :unlock_token]
  @blank ~r/(*UCP)\A\s*\z/u

  def digest(column, value, secret) when column in @columns and is_binary(secret) do
    if blank?(value),
      do: false,
      else: :crypto.mac(:hmac, :sha256, key(column, secret), value) |> Base.encode16(case: :lower)
  end

  def blank?(value), do: not is_binary(value) or Regex.match?(@blank, value)
  def token_error(raw), do: if(blank?(raw), do: :blank_token, else: :invalid)

  def key(column, secret) when column in @columns and is_binary(secret) do
    cache = {__MODULE__, column, :crypto.hash(:sha256, secret)}

    with nil <- :persistent_term.get(cache, nil) do
      key = :crypto.pbkdf2_hmac(:sha, secret, "Devise #{column}", 65_536, 64)
      :persistent_term.put(cache, key)
      :telemetry.execute([:dawarich, :auth, :recovery, :token_key], %{}, %{column: column})
      key
    end
  end

  def raw do
    :crypto.strong_rand_bytes(15)
    |> Base.url_encode64(padding: false)
    |> String.replace(
      ["l", "I", "O", "0"],
      &%{"l" => "s", "I" => "x", "O" => "y", "0" => "z"}[&1]
    )
  end
end
