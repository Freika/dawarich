defmodule Dawarich.Auth.RegistrationSetting do
  @moduledoc false

  @key "dawarich/registration_enabled"
  @entry <<0, 0x11, 1, -1.0::little-float-64, -1::little-signed-32, 4, 8>>

  def fetch(env \\ System.get_env(), command \\ &Dawarich.Redis.cache_command(&1, 1_000)) do
    case command.(["GET", @key]) do
      {:ok, nil} -> {:ok, env["ALLOW_EMAIL_PASSWORD_REGISTRATION"] == "true"}
      {:ok, <<@entry::binary, ?T>>} -> {:ok, true}
      {:ok, <<@entry::binary, value>>} when value in [?F, ?0] -> {:ok, false}
      _ -> :error
    end
  end
end
