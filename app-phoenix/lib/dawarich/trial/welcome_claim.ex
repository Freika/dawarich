defmodule Dawarich.Trial.WelcomeClaim do
  @moduledoc false
  alias Dawarich.RailsCache.Wire
  alias Dawarich.Trial.WelcomeToken
  @prefix "trial_welcome:consumed:"

  def supported?(jti),
    do: is_binary(jti) and String.valid?(jti) and byte_size(@prefix <> jti) <= 1024

  def claim(jti, exp, now, command) do
    if supported?(jti) do
      with {:ok, exp} <- WelcomeToken.integer(exp) do
        ttl = max(exp - now, 60)
        bytes = Wire.encode_boolean(true, expires_at: now + ttl)

        case command.(["SET", @prefix <> jti, bytes, "NX", "PX", Integer.to_string(ttl * 1000)]) do
          {:ok, "OK"} -> :claimed
          {:ok, nil} -> :consumed
          {:error, reason} -> {:error, reason}
          _ -> {:error, :unexpected_response}
        end
      else
        _ -> {:error, :unsupported_expiry}
      end
    else
      {:error, :unsupported_key}
    end
  rescue
    _ -> {:error, :claim_failed}
  catch
    _, _ -> {:error, :claim_failed}
  end
end
