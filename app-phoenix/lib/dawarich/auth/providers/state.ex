defmodule Dawarich.Auth.Providers.State do
  @moduledoc false
  @keys ~w(omniauth.state omniauth.nonce omniauth.pkce.verifier)

  def start(session, nonce \\ false) do
    state = random()
    session = session |> Map.drop(@keys) |> Map.put("omniauth.state", state)
    session = if nonce, do: Map.put(session, "omniauth.nonce", random()), else: session
    {state, session}
  end

  def take(session, params) do
    stored = session["omniauth.state"]
    supplied = params["state"]
    clean = Map.drop(session, @keys)

    if is_binary(stored) and stored != "" and is_binary(supplied) and
         Plug.Crypto.secure_compare(stored, supplied) do
      {:ok, %{nonce: session["omniauth.nonce"], verifier: session["omniauth.pkce.verifier"]},
       clean}
    else
      {:error, :csrf_detected, clean}
    end
  end

  def random, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
