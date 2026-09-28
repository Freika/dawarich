defmodule Dawarich.Accounts do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.Accounts.User
  alias Dawarich.Repo

  @remember_for 14 * 24 * 60 * 60
  @unlock_in 60 * 60

  def remember_for, do: @remember_for
  def unlock_in, do: @unlock_in

  @spec get(integer()) :: %User{} | nil
  def get(id) when is_integer(id) do
    case find(id) do
      %User{} = user -> if unlocked?(user, DateTime.utc_now()), do: user
      nil -> nil
    end
  end

  def get(_id), do: nil

  @spec from_session(map(), DateTime.t()) :: %User{} | {:locked, %User{}} | nil
  def from_session(%{"warden.user.user.key" => [[id], salt]}, now)
      when is_integer(id) and is_binary(salt) do
    with %User{} = user <- find(id),
         value when is_binary(value) <- salt(user),
         true <- Plug.Crypto.secure_compare(value, salt) do
      if unlocked?(user, now), do: user, else: {:locked, user}
    else
      _ -> nil
    end
  end

  def from_session(_session, _now), do: nil

  @spec from_remember_cookie(term(), DateTime.t()) :: %User{} | nil
  def from_remember_cookie([[id], token, generated_at], now)
      when is_integer(id) and is_binary(token) do
    with %User{} = user <- find(id),
         true <- unlocked?(user, now),
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

  defp find(id), do: User |> where([u], u.id == ^id and is_nil(u.deleted_at)) |> Repo.one()

  defp unlocked?(%User{locked_at: nil}, _now), do: true

  defp unlocked?(%User{locked_at: at}, now),
    do: DateTime.compare(at, DateTime.add(now, -@unlock_in)) == :lt

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
