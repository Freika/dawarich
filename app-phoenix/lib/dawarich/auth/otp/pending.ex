defmodule Dawarich.Auth.Otp.Pending do
  @moduledoc false
  @keys ~w(otp_user_id otp_challenge_at otp_failed_attempts otp_remember_me)

  def start(session, id, remember, now)
      when is_map(session) and is_integer(id) and is_integer(now) do
    Map.merge(session, %{
      "otp_user_id" => id,
      "otp_challenge_at" => now,
      "otp_remember_me" => remember == "1"
    })
  end

  def valid(session, now) do
    id = session["otp_user_id"]
    at = session["otp_challenge_at"]
    remember = session["otp_remember_me"]

    cond do
      is_nil(id) or is_nil(at) -> :expired
      not is_integer(id) or not timestamp?(at) -> {:handoff, :pending}
      remember not in [nil, false, true] -> {:handoff, :pending}
      at > now - 300 -> {:ok, id, remember == true}
      true -> :expired
    end
  end

  def clear(session), do: Map.drop(session, @keys)

  defp timestamp?(at) when is_integer(at), do: match?({:ok, _}, DateTime.from_unix(at))
  defp timestamp?(_), do: false
end
