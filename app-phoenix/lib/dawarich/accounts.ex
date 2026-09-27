defmodule Dawarich.Accounts do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.Accounts.User
  alias Dawarich.Repo

  @remember_for 14 * 24 * 60 * 60
  @unlock_in 60 * 60

  def remember_for, do: @remember_for

  def from_session(%{"warden.user.user.key" => [[id], salt]}, now)
      when is_integer(id) and is_binary(salt) do
    with %User{} = user <- active(id, now),
         value when is_binary(value) <- salt(user),
         true <- Plug.Crypto.secure_compare(value, salt) do
      user
    else
      _ -> nil
    end
  end

  def from_session(_session, _now), do: nil

  def from_remember_cookie([[id], token, generated_at], now)
      when is_integer(id) and is_binary(token) do
    with %User{} = user <- active(id, now),
         value when is_binary(value) and value != "" <- salt(user),
         true <- Plug.Crypto.secure_compare(value, token),
         {:ok, at} <- generated(generated_at),
         :gt <- DateTime.compare(at, DateTime.add(now, -@remember_for)),
         %DateTime{} = created <- user.remember_created_at,
         :gt <- DateTime.compare(at, created) do
      user
    else
      _ -> nil
    end
  end

  def from_remember_cookie(_payload, _now), do: nil

  defp active(id, now) do
    User
    |> where([u], u.id == ^id and is_nil(u.deleted_at))
    |> Repo.one()
    |> unlocked(now)
  end

  defp unlocked(nil, _now), do: nil
  defp unlocked(%User{locked_at: nil} = user, _now), do: user

  defp unlocked(%User{locked_at: at} = user, now) do
    if DateTime.compare(at, DateTime.add(now, -@unlock_in)) == :lt, do: user
  end

  defp salt(%User{encrypted_password: nil}), do: nil
  defp salt(%User{encrypted_password: password}), do: String.slice(password, 0, 29)

  defp generated(value) when is_binary(value) do
    if value =~ ~r/\A\d+\.\d+\z/ do
      {seconds, ""} = Float.parse(value)
      DateTime.from_unix(round(seconds * 1_000_000), :microsecond)
    else
      with {:ok, at, _offset} <- DateTime.from_iso8601(value), do: {:ok, at}
    end
  rescue
    _ in [ArgumentError, ArithmeticError] -> :error
  end

  defp generated(_value), do: :error
end
