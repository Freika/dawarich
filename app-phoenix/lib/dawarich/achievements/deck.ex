defmodule Dawarich.Achievements.Deck do
  @moduledoc false
  alias Dawarich.RubyInteger

  @fields ~w(id user_id kind key claim_token claimed_at seen_at created_at updated_at)a
  @columns Enum.map_join(@fields, ",", &Atom.to_string/1)

  def claim(repo, user_id, params, context) do
    {:ok, result} =
      repo.transaction(fn ->
        Map.get(context, :hook, fn _ -> :ok end).(:before_lock)

        case query(repo, "SELECT id FROM users WHERE id=$1 FOR UPDATE", [user_id]) do
          [] -> nil
          [_] -> reserve(repo, user_id, params, context, stamp(context))
        end
      end)

    result
  end

  defp reserve(repo, user_id, params, context, now) do
    active =
      event(
        repo,
        "WHERE user_id=$1 AND seen_at IS NULL AND claimed_at >= $2 ORDER BY id LIMIT 1",
        [user_id, NaiveDateTime.add(now, -45)]
      )

    bound = params["batch_end_id"]

    cond do
      active && active.claim_token != params["claim_token"] ->
        :busy

      active ->
        finish(repo, active, active.claim_token, bound, now)

      true ->
        bound = bound || maximum(repo, user_id)

        if bound do
          case available(repo, user_id, bound) do
            nil -> nil
            event -> finish(repo, event, token(context), bound, now)
          end
        end
    end
  end

  defp finish(repo, event, token, bound, now) do
    if event.claimed_at != now or event.claim_token != token do
      query(
        repo,
        "UPDATE achievement_unlock_events SET claimed_at=$2,claim_token=$3,updated_at=$2 WHERE id=$1",
        [event.id, now, token]
      )
    end

    bound = bound || maximum(repo, event.user_id)

    [[remaining]] =
      query(
        repo,
        "SELECT count(*) FROM achievement_unlock_events WHERE user_id=$1 AND seen_at IS NULL AND id BETWEEN 0 AND $2",
        [event.user_id, RubyInteger.to_i(bound)]
      )

    event = event(repo, "WHERE id=$1", [event.id])
    %{event: event, remaining: remaining, batch_end_id: bound}
  end

  defp available(repo, user_id, bound),
    do:
      event(
        repo,
        "WHERE user_id=$1 AND seen_at IS NULL AND id BETWEEN 0 AND $2 ORDER BY id LIMIT 1",
        [user_id, RubyInteger.to_i(bound)]
      )

  defp maximum(repo, user_id) do
    [[id]] =
      query(
        repo,
        "SELECT max(id) FROM achievement_unlock_events WHERE user_id=$1 AND seen_at IS NULL",
        [user_id]
      )

    id
  end

  defp event(repo, clause, args) do
    case query(repo, "SELECT #{@columns} FROM achievement_unlock_events " <> clause, args) do
      [] -> nil
      [row] -> @fields |> Enum.zip(row) |> Map.new()
    end
  end

  defp token(context),
    do:
      Map.get(context, :token, fn ->
        Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
      end).()

  defp stamp(context) do
    case context.clock.() do
      %DateTime{} = now -> DateTime.to_naive(now)
      %NaiveDateTime{} = now -> now
    end
  end

  defp query(repo, sql, args), do: repo.query!(sql, args, log: false, prepare: :unnamed).rows
end
