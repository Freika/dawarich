defmodule Dawarich.Auth.RegistrationSetting do
  @moduledoc false

  @key "dawarich/registration_enabled"
  @entry <<0, 0x11, 1, -1.0::little-float-64, -1::little-signed-32, 4, 8>>

  def fetch(env \\ System.get_env(), command \\ &Dawarich.Redis.cache_command(&1, 1_000)) do
    case command.(["GET", @key]) do
      {:ok, nil} -> {:ok, env["ALLOW_EMAIL_PASSWORD_REGISTRATION"] == "true"}
      {:ok, <<@entry::binary, ?T>>} -> {:ok, true}
      {:ok, <<@entry::binary, ?F>>} -> {:ok, false}
      {:ok, <<@entry::binary, ?0>>} -> {:ok, nil}
      _ -> :error
    end
  end

  def put(value, command \\ &Dawarich.Redis.cache_command(&1, 1_000))
      when value in [true, false, nil] do
    case command.(["SET", @key, Dawarich.RailsCache.Wire.encode_boolean(value, expires_at: nil)]) do
      {:ok, "OK"} -> :ok
      _ -> {:error, :cache}
    end
  end
end
