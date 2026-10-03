defmodule Dawarich.CLI.RawData do
  @moduledoc false

  import Dawarich.CLI, only: [puts: 2, lines: 2, fail: 2, header: 3, rule: 0]

  alias Dawarich.RawData.{ArchiveFormat, Archiver, Archives, Clearer, Restorer, Verifier}
  alias Dawarich.{RubyInteger, Storage}

  @users "SELECT id FROM users WHERE deleted_at IS NULL AND id > $1 ORDER BY id LIMIT 1000"
  @unverified "SELECT id FROM points_raw_data_archives WHERE verified_at IS NULL ORDER BY id"
  @unverified_month """
  SELECT id FROM points_raw_data_archives
  WHERE user_id = $1 AND year = $2 AND month = $3 AND verified_at IS NULL ORDER BY chunk_number
  """
  @email "SELECT email FROM users WHERE id = $1 AND deleted_at IS NULL"
  @vacuum "Run VACUUM ANALYZE points; to reclaim space and update statistics."

  def vacuum, do: @vacuum

  def restore([user, year, month], ctx) do
    ctx = ready(ctx)
    {user, year, month} = {to_i(user), to_i(year), to_i(month)}
    header(ctx, "Restoring raw_data to DATABASE", month_line(user, year, month))
    Restorer.restore_month(ctx.repo, ctx.storage, ctx.archive_key, user, year, month)

    lines(ctx, [
      "",
      "✓ Restoration complete!",
      "",
      "Points in #{year}-#{month} now have raw_data in database.",
      "Run VACUUM ANALYZE points; to update statistics."
    ])

    0
  end

  def restore(_args, ctx), do: fail(ctx, "usage: dawarich raw-data restore USER_ID YEAR MONTH")

  def restore_all([user], ctx) do
    ctx = ready(ctx)
    user = to_i(user)

    email =
      case ctx.repo.query!(@email, [user], log: false).rows do
        [[email]] -> email
        [] -> raise ~s(Couldn't find User with 'id'=#{user} [WHERE "users"."deleted_at" IS NULL])
      end

    months = Restorer.months(ctx.repo, user)
    count = length(months)

    lines(ctx, [
      rule(),
      "  Restoring ALL archives for user",
      "  #{email} (ID: #{user})",
      rule(),
      ""
    ])

    lines(ctx, ["Found #{count} months to restore", ""])

    months
    |> Enum.with_index(1)
    |> Enum.each(fn {{year, month}, index} ->
      puts(ctx, "[#{index}/#{count}] Restoring #{year}-#{pad(month)}...")
      Restorer.restore_month(ctx.repo, ctx.storage, ctx.archive_key, user, year, month)
    end)

    lines(ctx, ["", "✓ All archives restored for user #{user}!"])
    0
  end

  def restore_all(_args, ctx), do: fail(ctx, "usage: dawarich raw-data restore-all USER_ID")

  def verify([user, year, month], ctx) do
    ctx = ready(ctx)
    {user, year, month} = {to_i(user), to_i(year), to_i(month)}
    header(ctx, "Verifying Archives", month_line(user, year, month))
    verify_ids(ctx, ids(ctx, @unverified_month, [user, year, month]))
    lines(ctx, ["", "✓ Verification complete!"])
    0
  end

  def verify([], ctx) do
    ctx = ready(ctx)
    header(ctx, "Verifying All Unverified Archives", nil)
    {verified, failed} = verify_ids(ctx, ids(ctx, @unverified, []))
    lines(ctx, ["", "Verified: #{verified}", "Failed: #{failed}", "", "✓ Verification complete!"])
    0
  end

  def verify(_args, ctx), do: fail(ctx, "usage: dawarich raw-data verify [USER_ID YEAR MONTH]")

  def clear_verified([user, year, month], ctx) do
    {user, year, month} = {to_i(user), to_i(year), to_i(month)}
    header(ctx, "Clearing Verified Archives", month_line(user, year, month))
    Clearer.clear_month(ctx.repo, user, year, month)
    lines(ctx, ["", "✓ Clearing complete!", "", @vacuum])
    0
  end

  def clear_verified([], ctx) do
    header(ctx, "Clearing All Verified Archives", nil)
    cleared = Clearer.clear_all(ctx.repo, nil)
    lines(ctx, ["", "Points cleared: #{cleared}", "", "✓ Clearing complete!", "", @vacuum])
    0
  end

  def clear_verified(_args, ctx),
    do: fail(ctx, "usage: dawarich raw-data clear-verified [USER_ID YEAR MONTH]")

  def archive([], ctx) do
    ctx = ready(ctx)

    lines(ctx, [
      rule(),
      "  Archiving Raw Data (2+ months old data)",
      rule(),
      "",
      "This will archive points.raw_data for months 2+ months old.",
      "Raw data will NOT be cleared yet - use verify and clear_verified tasks.",
      "This is safe to run multiple times (idempotent).",
      ""
    ])

    stats = archive_all(ctx)

    lines(ctx, [
      "",
      rule(),
      "  Archival Complete",
      rule(),
      "",
      "Chunks processed: #{stats.processed}",
      "Points archived: #{stats.archived}",
      "Failures: #{stats.failed}",
      ""
    ])

    if stats.archived > 0,
      do:
        lines(ctx, [
          "Next steps:",
          "1. Verify archives: dawarich raw-data verify",
          "2. Clear verified data: dawarich raw-data clear-verified",
          "3. Check stats: dawarich raw-data status"
        ])

    0
  end

  def archive(_args, ctx), do: fail(ctx, "usage: dawarich raw-data archive")

  def archive_full([], ctx) do
    ctx = ready(ctx)

    lines(ctx, [
      rule(),
      "  Full Archive Workflow",
      "  (Archive → Verify → Clear)",
      rule(),
      "",
      "▸ Step 1/3: Archiving..."
    ])

    stats = archive_all(ctx)
    lines(ctx, ["  ✓ Archived #{stats.archived} points", "", "▸ Step 2/3: Verifying..."])
    {verified, failed} = verify_ids(ctx, ids(ctx, @unverified, []))
    puts(ctx, "  ✓ Verified #{verified} archives")
    if failed > 0, do: verification_failed(ctx, failed)
    puts(ctx, "")
    puts(ctx, "▸ Step 3/3: Clearing verified data older than the cooling period...")
    cleared = Clearer.clear_all(ctx.repo, 7)

    lines(ctx, [
      "  ✓ Cleared #{cleared} points",
      "  Archives created this run become clearable after 7 days.",
      "",
      rule(),
      "  ✓ Full Archive Workflow Complete!",
      rule(),
      "",
      "Run VACUUM ANALYZE points; to reclaim space."
    ])

    0
  end

  def archive_full(_args, ctx), do: fail(ctx, "usage: dawarich raw-data archive-full")

  defp archive_all(ctx, after_id \\ 0, stats \\ %{processed: 0, archived: 0, failed: 0}) do
    case ids(ctx, @users, [after_id]) do
      [] ->
        stats

      users ->
        archive_all(ctx, List.last(users), Enum.reduce(users, stats, &archive_user(ctx, &1, &2)))
    end
  end

  defp archive_user(ctx, user, stats) do
    Archives.recover!(ctx.repo, ctx.storage, user)
    archive_pass(ctx, user, stats, 0)
  end

  defp archive_pass(ctx, user, stats, cursor) do
    me = self()
    on_result = &send(me, {:archived, &1})

    result =
      Archiver.pass(ctx.repo, ctx.storage, ctx.archive_key, user, cursor, on_result: on_result)

    stats = collect(stats)

    case result do
      {:continue, next} -> archive_pass(ctx, user, stats, next)
      :done -> stats
    end
  end

  defp collect(stats) do
    receive do
      {:archived, {:ok, count}} ->
        collect(%{stats | processed: stats.processed + 1, archived: stats.archived + count})

      {:archived, {:error, _reason}} ->
        collect(%{stats | failed: stats.failed + 1})
    after
      0 -> stats
    end
  end

  defp verify_ids(ctx, ids) do
    Enum.reduce(ids, {0, 0}, fn id, {verified, failed} ->
      if verify_one(ctx, id) == :ok, do: {verified + 1, failed}, else: {verified, failed + 1}
    end)
  end

  defp verify_one(ctx, id) do
    Verifier.verify(ctx.repo, ctx.storage, ctx.archive_key, id)
  rescue
    _ -> :error
  end

  defp verification_failed(ctx, failed) do
    lines(ctx, [
      "  ✗ Failed to verify #{failed} archives",
      "",
      "⚠ Some archives failed verification. Data NOT cleared for safety.",
      "Please investigate failed archives before running clear_verified."
    ])

    raise "Verification failed for #{failed} archives. Aborting to prevent data loss."
  end

  def ready(ctx) do
    ctx
    |> Map.put_new_lazy(:storage, fn -> storage!(ctx.env) end)
    |> Map.put_new_lazy(:archive_key, fn -> ArchiveFormat.key(ctx.env) end)
  end

  defp storage!(env) do
    root =
      env["APP_PATH"] ||
        raise "APP_PATH is not set: set it to the Dawarich directory that holds storage/ (/var/app in the image)"

    storage = Storage.config!(env, root)

    if storage.service == "local" and not File.dir?(storage.root),
      do:
        raise(
          "#{storage.root} is not a directory: APP_PATH must be the Dawarich directory that holds storage/"
        )

    storage
  end

  def ids(ctx, sql, params), do: ctx.repo.query!(sql, params, log: false).rows |> List.flatten()
  defp to_i(value), do: RubyInteger.to_i(value)
  defp month_line(user, year, month), do: "  User: #{user} | Month: #{year}-#{pad(month)}"
  def pad(month), do: month |> Integer.to_string() |> String.pad_leading(2, "0")
end
