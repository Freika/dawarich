defmodule Dawarich.Trial.WelcomeClaim do
  @moduledoc false
  alias Dawarich.State
  alias Dawarich.Trial.WelcomeToken
  @prefix "trial_welcome:consumed:"

  def supported?(jti),
    do: is_binary(jti) and String.valid?(jti) and byte_size(@prefix <> jti) <= 1024

  def claim(jti, exp, now, repo) do
    if supported?(jti) do
      with {:ok, exp} <- WelcomeToken.integer(exp) do
        ttl = max(exp - now, 60)
        key = @prefix <> "sha256:" <> Base.encode16(:crypto.hash(:sha256, jti), case: :lower)
        if State.claim(repo, key, ttl), do: :claimed, else: :consumed
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
