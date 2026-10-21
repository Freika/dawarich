defmodule Dawarich.Auth.Providers.Pkce do
  @moduledoc false
  alias Dawarich.Auth.Providers.State

  def authorize(session) do
    verifier = State.random()
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    {%{code_challenge: challenge, code_challenge_method: "S256"},
     Map.put(session, "omniauth.pkce.verifier", verifier)}
  end

  def exchange(pending), do: %{code_verifier: pending.verifier}
end
