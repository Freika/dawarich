defmodule Dawarich.Maps.Dependencies.Principal do
  @moduledoc false
  alias Dawarich.{Accounts, UserSettings}
  alias Dawarich.Accounts.Scope

  @fields ~w(id email first_name last_name theme admin status plan active_until subscription_source changelog_consent points_count)a
  @settings ~w(timezone locale onboarding_completed live_map_enabled)

  def scope(user, locale) do
    Scope.for_user(Map.put(safe(user), :session_identity, identity(user)), locale)
  end

  def actor(%Scope{user: %{id: id, session_identity: proof}}, now)
      when is_binary(proof) and byte_size(proof) == 64 do
    user = Accounts.get(id)

    cond do
      is_nil(user) or not Plug.Crypto.secure_compare(proof, identity(user)) ->
        {:error, :stale_session}

      user.status in [0, 3] or expired?(user.active_until, now) ->
        {:error, :unauthorized}

      true ->
        {:ok, user}
    end
  end

  def actor(_, _), do: {:error, :stale_session}

  def safe(user) do
    user
    |> Map.take(@fields)
    |> Map.put(:settings, Map.take(UserSettings.get(user), @settings))
  end

  def identity(%{encrypted_password: hash}) when is_binary(hash) and byte_size(hash) >= 29,
    do: :crypto.hash(:sha256, binary_part(hash, 0, 29)) |> Base.encode16(case: :lower)

  def identity(_), do: ""

  defp expired?(nil, _), do: false
  defp expired?(%DateTime{} = until, now), do: DateTime.compare(until, now) == :lt
  defp expired?(_, _), do: true
end
