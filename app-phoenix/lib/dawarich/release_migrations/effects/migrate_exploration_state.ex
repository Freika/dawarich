defmodule Dawarich.ReleaseMigrations.Effects.MigrateExplorationState do
  @moduledoc false

  import Dawarich.ReleaseMigration, only: [exists?: 3]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @renames [
    {"explorer_germany", "country_de"},
    {"explorer_usa", "country_us"},
    {"explorer_europe", "continent_europe"}
  ]

  @legacy_keys Enum.map(@renames, &elem(&1, 0)) ++ ~w[border_hopper globetrotter world_traveler]

  @exploration "exploration"

  @legacy_rows """
  SELECT id, user_id, achievement_key, state, sharing_enabled, sharing_uuid
  FROM achievement_progresses WHERE achievement_key IN ($1, $2, $3, $4, $5, $6)
  """

  @exploration_row """
  SELECT id, state FROM achievement_progresses WHERE user_id = $1 AND achievement_key = $2 LIMIT 1
  """

  @key_taken """
  SELECT 1 FROM achievement_progresses WHERE achievement_key = $1 AND id != $2 AND user_id = $3
  """

  @delete_taken_awards """
  DELETE FROM user_achievements award WHERE award.achievement_key = $1 AND EXISTS (
    SELECT 1 FROM user_achievements taken WHERE taken.user_id = award.user_id AND taken.achievement_key = $2
  )
  """

  def run(repo) do
    rows =
      for [id, user_id, key, state, enabled, uuid] <-
            repo.query!(@legacy_rows, @legacy_keys, log: false).rows do
        %{
          id: id,
          user_id: user_id,
          key: key,
          state: state,
          carrier: enabled or Ruby.present?(uuid)
        }
      end

    by_user = Enum.group_by(rows, & &1.user_id)

    for user_id <- rows |> Enum.map(& &1.user_id) |> Enum.uniq() do
      merge_user(repo, user_id, Map.fetch!(by_user, user_id))
    end

    rename_awards(repo)
    :ok
  end

  defp merge_user(repo, user_id, rows) do
    store_exploration(repo, user_id, Enum.reduce(rows, %{}, &merge_earned/2))
    {carriers, disposable} = Enum.split_with(rows, & &1.carrier)

    repo.query!(
      "DELETE FROM achievement_progresses WHERE id = ANY ($1)",
      [Enum.map(disposable, & &1.id)],
      log: false
    )

    Enum.each(carriers, &update_carrier(repo, &1))
  end

  defp merge_earned(row, merged) do
    row.state
    |> fetch("earned")
    |> each_pair()
    |> Enum.reduce(merged, fn {code, earned_at}, acc ->
      current = acc[code]

      if is_nil(current) or less?(earned_at, current),
        do: Map.put(acc, code, earned_at),
        else: acc
    end)
  end

  defp store_exploration(repo, user_id, earned) do
    case repo.query!(@exploration_row, [user_id, @exploration], log: false).rows do
      [[id, state]] ->
        new_state = exploration_state(fetch(state, "earned"), earned)

        if new_state != state do
          repo.query!(
            "UPDATE achievement_progresses SET state = $1::text::jsonb, updated_at = NOW() WHERE id = $2",
            [json(new_state), id],
            log: false
          )
        end

      [] ->
        unless exists?(repo, "SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL", [user_id]),
               do: raise(Ruby.Error, "Validation failed: User must exist")

        repo.query!(
          "INSERT INTO achievement_progresses (user_id, achievement_key, state, created_at, updated_at) VALUES ($1, $2, $3::text::jsonb, NOW(), NOW())",
          [user_id, @exploration, json(exploration_state(%{}, earned))],
          log: false
        )
    end
  end

  defp exploration_state(previous, earned) when is_map(previous) do
    %{
      "earned" => Map.merge(previous, earned, fn _code, a, b -> earlier(a, b) end),
      "dwell" => %{},
      "cursor" => 0
    }
  end

  defp exploration_state(previous, _earned), do: Ruby.no_method!("merge", previous)

  defp update_carrier(repo, row) do
    key = rename(row.key)

    cond do
      key == row.key and row.state == %{} ->
        :ok

      key != row.key and exists?(repo, @key_taken, [key, row.id, row.user_id]) ->
        raise Ruby.Error, "Validation failed: Achievement key has already been taken"

      true ->
        repo.query!(
          "UPDATE achievement_progresses SET achievement_key = $1, state = '{}', updated_at = NOW() WHERE id = $2",
          [key, row.id],
          log: false
        )
    end
  end

  defp rename_awards(repo) do
    for {old, new} <- @renames do
      repo.query!(@delete_taken_awards, [old, new], log: false)

      repo.query!(
        "UPDATE user_achievements SET achievement_key = $2, updated_at = NOW() WHERE achievement_key = $1",
        [old, new],
        log: false
      )
    end
  end

  defp rename(key) do
    case List.keyfind(@renames, key, 0) do
      {^key, new} -> new
      nil -> key
    end
  end

  defp fetch(map, key) when is_map(map), do: Map.get(map, key, %{})

  defp fetch(list, _key) when is_list(list),
    do: raise(Ruby.Error, "no implicit conversion of String into Integer")

  defp fetch(value, _key), do: Ruby.no_method!("fetch", value)

  defp each_pair(map) when is_map(map), do: map

  defp each_pair(value) when is_list(value),
    do: raise(Ruby.Unreproducible, "cannot reproduce Ruby's each over #{Ruby.instance(value)}")

  defp each_pair(value), do: Ruby.no_method!("each", value)

  defp less?(a, b) when (is_binary(a) and is_binary(b)) or (is_number(a) and is_number(b)),
    do: a < b

  defp less?(a, b), do: cannot_compare!(a, b)

  defp earlier(a, b) when (is_binary(a) and is_binary(b)) or (is_number(a) and is_number(b)),
    do: min(a, b)

  defp earlier(same, same), do: same
  defp earlier(a, b), do: cannot_compare!(a, b)

  defp cannot_compare!(a, b) do
    raise Ruby.Unreproducible,
          "cannot reproduce Ruby's comparison of #{Ruby.instance(a)} with #{Ruby.instance(b)}"
  end

  defp json(state), do: IO.iodata_to_binary(Ruby.json(state))
end
