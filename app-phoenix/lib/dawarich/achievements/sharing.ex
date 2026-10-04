defmodule Dawarich.Achievements.Sharing do
  @moduledoc false
  alias Dawarich.Achievements.Registry

  @false_values [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  def call(repo, user_id, key, input, context) do
    cond do
      is_nil(Registry.find(key)) ->
        {:error, :not_found}

      not supported?(input) ->
        {:unsupported, :input}

      query(repo, "SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL", [user_id]) == [] ->
        {:unsupported, :actor}

      true ->
        repo.transaction(fn -> share(repo, user_id, key, input, context) end)
    end
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, {:terminal, error.__struct__}}
  end

  defp supported?(input) when is_map(input) do
    not Map.has_key?(input, "enabled") or
      (input["enabled"] not in [nil, ""] and
         (is_boolean(input["enabled"]) or is_number(input["enabled"]) or
            is_binary(input["enabled"])))
  end

  defp supported?(_), do: false

  defp share(repo, user_id, key, input, context) do
    hook = Map.get(context, :hook, fn _ -> :ok end)
    hook.(:before_insert)
    now = stamp(context)

    query(
      repo,
      "INSERT INTO achievement_progresses(user_id,achievement_key,created_at,updated_at) VALUES($1,$2,$3,$3) ON CONFLICT(user_id,achievement_key) DO NOTHING",
      [user_id, key, now]
    )

    hook.(:before_lock)

    [[id, current, uuid]] =
      query(
        repo,
        "SELECT id,sharing_enabled,sharing_uuid FROM achievement_progresses WHERE user_id=$1 AND achievement_key=$2 ORDER BY id LIMIT 1 FOR UPDATE",
        [user_id, key]
      )

    enabled =
      if Map.has_key?(input, "enabled"),
        do: input["enabled"] not in @false_values,
        else: not current

    next_uuid = uuid || Ecto.UUID.generate()

    if enabled != current or is_nil(uuid) do
      query(
        repo,
        "UPDATE achievement_progresses SET sharing_enabled=$2,sharing_uuid=$3,updated_at=$4 WHERE id=$1",
        [id, enabled, next_uuid, stamp(context)]
      )
    end

    %{enabled: enabled, uuid: next_uuid}
  end

  defp stamp(context) do
    case context.clock.() do
      %DateTime{} = now -> DateTime.to_naive(now)
      %NaiveDateTime{} = now -> now
    end
  end

  defp query(repo, sql, args), do: repo.query!(sql, args, log: false, prepare: :unnamed).rows
end
