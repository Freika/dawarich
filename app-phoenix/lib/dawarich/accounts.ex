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

  def public_owner(id) when is_integer(id), do: find(id)
  def public_owner(_id), do: nil

  def by_api_key(key) when is_binary(key) do
    from(u in "users",
      where: u.api_key == ^key and is_nil(u.deleted_at),
      limit: 1,
      select: %{
        id: u.id,
        email: u.email,
        status: u.status,
        active_until: u.active_until,
        plan: u.plan,
        subscription_source: u.subscription_source,
        timezone: fragment("?->'timezone'", u.settings)
      }
    )
    |> Repo.one(log: false)
  end

  def settings(user_id) do
    [[settings]] = Repo.query!("SELECT settings FROM users WHERE id = $1", [user_id]).rows
    settings
  end

  def persist_locale(id, locale) do
    %{rows: rows} =
      Repo.query!(
        """
        UPDATE public.users
        SET settings = CASE WHEN jsonb_typeof(settings) = 'object' THEN settings ELSE '{}'::jsonb END
          || jsonb_build_object('locale', $1::text),
          updated_at = $2
        WHERE id = $3
        RETURNING settings
        """,
        [locale, NaiveDateTime.utc_now(), id]
      )

    case rows do
      [[settings]] -> settings
      [] -> nil
    end
  end

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

  @spec from_remember_cookie(term(), DateTime.t()) :: %User{} | {:locked, %User{}} | nil
  def from_remember_cookie([[id], _token, _generated_at] = payload, now) when is_integer(id) do
    with %User{} = user <- find(id),
         true <- remembered?(user, payload, now) do
      if unlocked?(user, now), do: user, else: {:locked, user}
    else
      _ -> nil
    end
  end

  def from_remember_cookie(_payload, _now), do: nil

  def remembered?(
        %{id: id, encrypted_password: hash, remember_created_at: created},
        [[id], token, generated_at],
        now
      )
      when is_binary(hash) and hash != "" and is_binary(token) do
    with true <- Plug.Crypto.secure_compare(String.slice(hash, 0, 29), token),
         {:ok, at} <- generated(generated_at),
         :gt <- DateTime.compare(at, DateTime.add(now, -@remember_for)),
         %DateTime{} <- created,
         :gt <- DateTime.compare(at, created) do
      true
    else
      _ -> false
    end
  end

  def remembered?(_user, _payload, _now), do: false

  def remember_generated_at(%DateTime{} = at) do
    microseconds = DateTime.to_unix(at, :microsecond)

    fraction =
      microseconds
      |> rem(1_000_000)
      |> Integer.to_string()
      |> String.pad_leading(6, "0")
      |> String.trim_trailing("0")

    "#{div(microseconds, 1_000_000)}.#{if fraction == "", do: "0", else: fraction}"
  end

  def unlocked?(%{locked_at: nil}, _now), do: true

  def unlocked?(%{locked_at: at}, now),
    do: DateTime.compare(at, DateTime.add(now, -@unlock_in)) == :lt

  defp find(id), do: User |> where([u], u.id == ^id and is_nil(u.deleted_at)) |> Repo.one()

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
