defmodule Dawarich.Sharing.Resources do
  @moduledoc false
  alias Dawarich.{Repo, SharedLinks}
  alias Dawarich.ShareManagement.Read

  @types [:hub, :live, :trip, :track, :timeline, :shared, :month, :digest, :achievement]
  @keys %{
    hub: [:type, :owner_id],
    live: [:type, :owner_id],
    timeline: [:type, :owner_id],
    trip: [:type, :owner_id, :id],
    track: [:type, :owner_id, :id],
    shared: [:type, :owner_id, :id],
    month: [:type, :owner_id, :year, :month],
    digest: [:type, :owner_id, :year],
    achievement: [:type, :owner_id, :key]
  }

  def admit(%{type: type, owner_id: owner} = resource, actor) when type in @types do
    cond do
      owner != actor -> {:error, :unauthorized}
      Enum.sort(Map.keys(resource)) != Enum.sort(@keys[type]) -> {:error, :invalid_input}
      not shape?(resource) -> {:error, :invalid_input}
      true -> :ok
    end
  end

  def admit(_, _), do: {:error, :invalid_input}

  defp shape?(%{type: type, id: id}) when type in [:trip, :track], do: is_integer(id) and id > 0
  defp shape?(%{type: :shared, id: id}), do: SharedLinks.canonical?(id)

  defp shape?(%{type: :month, year: year, month: month}),
    do: is_integer(year) and year in 1..9999 and is_integer(month) and month in 1..12

  defp shape?(%{type: :digest, year: year}), do: is_integer(year) and year in 1..9999

  defp shape?(%{type: :achievement, key: key}),
    do: is_binary(key) and not is_nil(Dawarich.Achievements.Registry.find(key))

  defp shape?(_), do: true

  def access(user, %{type: type}, ctx) when type in [:month, :digest] do
    if Dawarich.Entitlements.future?(user.active_until, ctx.now) and
         (type != :month or Dawarich.Entitlements.full_access?(user, ctx.self_hosted, ctx.now)),
       do: :ok,
       else: {:error, :expired}
  end

  def access(_, _, _), do: :ok

  def read(user, resource, params, ctx, locale) when is_map(params) do
    result =
      case resource.type do
        :hub ->
          Read.hub(user, params, ctx.now)

        :live ->
          Read.live(user, ctx.now)

        :trip ->
          Read.trip(user, resource.id, ctx.now)

        :track ->
          Read.track(user, resource.id, ctx.now, locale)

        :timeline ->
          Read.timeline(user, params, ctx.now)

        :shared ->
          Read.owned(user, resource.id)

        :month ->
          report(user.id, "stats", "year=$2 AND month=$3", [resource.year, resource.month])

        :digest ->
          report(user.id, "digests", "year=$2 AND period_type=1", [resource.year])

        :achievement ->
          achievement(user.id, resource.key)
      end

    case result do
      {:ok, _} = ok -> ok
      {:error, 404} -> {:error, :not_found}
      _ -> {:error, :invalid_input}
    end
  end

  def read(_, _, _, _, _), do: {:error, :invalid_input}

  defp report(user, table, condition, args) do
    case Repo.query!(
           "SELECT sharing_uuid::text,sharing_settings FROM #{table} WHERE user_id=$1 AND #{condition} LIMIT 1",
           [user | args],
           log: false
         ).rows do
      [[uuid, settings]] -> {:ok, %{uuid: uuid, settings: settings}}
      [] -> {:error, 404}
    end
  end

  defp achievement(user, key) do
    case Repo.query!(
           "SELECT sharing_uuid,sharing_enabled FROM achievement_progresses WHERE user_id=$1 AND achievement_key=$2 LIMIT 1",
           [user, key],
           log: false
         ).rows do
      [[uuid, enabled]] -> {:ok, %{uuid: uuid, enabled: enabled}}
      [] -> {:ok, %{uuid: nil, enabled: false}}
    end
  end

  def sanitize(%_{} = value), do: value

  def sanitize(value) when is_map(value) do
    value =
      if Map.has_key?(value, :magic_phrase),
        do:
          Map.put(
            value,
            :protected?,
            is_binary(value.magic_phrase) and String.trim(value.magic_phrase) != ""
          ),
        else: value

    value
    |> Map.drop([
      :magic_phrase,
      "magic_phrase",
      :user,
      :attrs,
      :body,
      :api_key,
      :encrypted_password
    ])
    |> Map.new(fn {key, item} -> {key, sanitize(item)} end)
  end

  def sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  def sanitize(value), do: value

  def public_ids(user) do
    Repo.query!(
      "SELECT id::text FROM shared_links WHERE user_id=$1 UNION SELECT sharing_uuid::text FROM stats WHERE user_id=$1 AND sharing_uuid IS NOT NULL UNION SELECT sharing_uuid::text FROM digests WHERE user_id=$1 AND sharing_uuid IS NOT NULL UNION SELECT sharing_uuid FROM achievement_progresses WHERE user_id=$1 AND sharing_uuid IS NOT NULL",
      [user],
      log: false
    ).rows
    |> List.flatten()
  end
end
