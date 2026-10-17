defmodule Dawarich.CLI.Places do
  @moduledoc false
  alias Dawarich.{CLI, Places.JobCommands}

  def backfill_names([], ctx) do
    :ok = JobCommands.bulk_name_fetch(ctx.repo)
    0
  end

  def backfill_names(_, ctx), do: CLI.fail(ctx, "usage: dawarich places backfill-names")

  def cleanup_suggested([], ctx) do
    cleanup(ctx.repo, ctx[:now] || DateTime.utc_now(), nil, 0)
    0
  end

  def cleanup_suggested(_, ctx), do: CLI.fail(ctx, "usage: dawarich places cleanup-suggested")

  def orphan_count([], ctx) do
    [[count]] =
      ctx.repo.query!(
        "SELECT count(*) FROM places p WHERE p.source=1 AND (p.note IS NULL OR p.note='') AND NOT EXISTS(SELECT 1 FROM visits v WHERE v.place_id=p.id) AND NOT EXISTS(SELECT 1 FROM taggings t WHERE t.taggable_type='Place' AND t.taggable_id=p.id)",
        [],
        log: false
      ).rows

    CLI.puts(ctx, to_string(count))
    0
  end

  def orphan_count(_, ctx), do: CLI.fail(ctx, "usage: dawarich places orphan-count")

  defp cleanup(repo, now, cursor, index) do
    batch =
      repo.query!(
        "SELECT id FROM users WHERE deleted_at IS NULL AND ($1::bigint IS NULL OR id>$1) ORDER BY id LIMIT 100",
        [cursor],
        log: false
      ).rows
      |> List.flatten()

    if batch != [] do
      last = List.last(batch)

      ids =
        repo.query!(
          "SELECT id FROM users WHERE deleted_at IS NULL AND ($1::bigint IS NULL OR id>$1) AND id<=$2",
          [cursor, last],
          log: false
        ).rows
        |> List.flatten()

      for {user, offset} <- Enum.with_index(ids),
          do:
            JobCommands.orphan_cleanup(
              repo,
              user,
              DateTime.add(now, (index + offset) * 100_000, :microsecond)
            )

      if length(batch) == 100, do: cleanup(repo, now, last, index + 100)
    end

    :ok
  end
end
