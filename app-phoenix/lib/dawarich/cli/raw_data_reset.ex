defmodule Dawarich.CLI.RawDataReset do
  @moduledoc false

  import Dawarich.CLI, only: [puts: 2, lines: 2, rule: 0, fail: 2]
  import Dawarich.CLI.RawData, only: [ready: 1, ids: 3, pad: 1, vacuum: 0]

  alias Dawarich.RawData.{Archives, Restorer}
  alias Dawarich.ReleaseMigration

  @counts """
  SELECT (SELECT count(*) FROM points_raw_data_archives),
         (SELECT count(*) FROM points WHERE raw_data_archived = true),
         (SELECT count(*) FROM points WHERE raw_data_archived = true AND raw_data = '{}'::jsonb)
  """
  @cleared_months """
  SELECT DISTINCT a.user_id, a.year, a.month FROM points_raw_data_archives a
  WHERE EXISTS (SELECT 1 FROM points p WHERE p.raw_data_archive_id = a.id AND p.raw_data = '{}'::jsonb)
  ORDER BY a.user_id, a.year, a.month
  """
  @unflag """
  UPDATE points SET raw_data_archived = false, raw_data_archive_id = NULL
  WHERE raw_data_archived = true AND raw_data <> '{}'::jsonb
  """
  @archives "SELECT id FROM points_raw_data_archives ORDER BY id"

  def reset_all([], ctx) do
    ctx = ready(ctx)
    [[archives, archived, cleared]] = ctx.repo.query!(@counts, [], log: false).rows

    lines(ctx, [
      rule(),
      "  RESET: Remove All Archives",
      "  Points will be restored as if never archived",
      rule(),
      "",
      "Archives to delete: #{archives}",
      "Points flagged as archived: #{archived}",
      "Points with cleared raw_data: #{cleared}",
      ""
    ])

    cond do
      archives == 0 and archived == 0 -> puts(ctx, "Nothing to reset.")
      not confirmed?(ctx) -> puts(ctx, "Aborted.")
      true -> reset(ctx, archives, cleared)
    end

    0
  end

  def reset_all(_args, ctx), do: fail(ctx, "usage: dawarich raw-data reset-all")

  defp reset(ctx, archives, cleared) do
    if cleared > 0 do
      puts(ctx, "▸ Step 1/3: Restoring cleared raw_data from archives...")

      for [user, year, month] <- ctx.repo.query!(@cleared_months, [], log: false).rows do
        puts(ctx, "  Restoring user #{user}, #{year}-#{pad(month)}...")
        Restorer.restore_month(ctx.repo, ctx.storage, ctx.archive_key, user, year, month)
      end

      puts(ctx, "  Done restoring.")
    else
      puts(ctx, "▸ Step 1/3: No cleared points to restore (skipped).")
    end

    Map.get(ctx, :before_unflag, fn -> :ok end).()
    lines(ctx, ["", "▸ Step 2/3: Resetting archival flags on points..."])
    puts(ctx, "  Reset #{ctx.repo.query!(@unflag, [], log: false).num_rows} points.")
    lines(ctx, ["", "▸ Step 3/3: Deleting archive records and files..."])

    kept = ctx |> ids(@archives, []) |> Enum.reject(&(destroy!(ctx, &1) == :ok))

    if kept != [],
      do:
        raise(
          "#{length(kept)} archives still hold points whose raw_data was cleared during the reset and were kept; run dawarich raw-data reset-all again"
        )

    lines(ctx, [
      "  Deleted #{archives} archive records.",
      "",
      rule(),
      "  Reset Complete!",
      rule(),
      "",
      "All points are now as if archival never happened.",
      vacuum()
    ])
  end

  defp destroy!(ctx, id) do
    case Archives.destroy(ctx.repo, ctx.storage, id) do
      :ok -> :ok
      {:error, :linked} -> :linked
      {:error, reason} -> raise "Archive #{id} could not be deleted (#{reason})"
    end
  end

  defp confirmed?(ctx), do: ctx.env["CONFIRM"] == "true" or prompt_yes?(ctx)

  defp prompt_yes?(ctx) do
    IO.write(ctx.out, "This is a destructive operation. Continue? (y/N) ")

    case IO.gets(ctx.stdin, "") do
      line when is_binary(line) ->
        line |> ReleaseMigration.ruby_strip() |> String.downcase() == "y"

      _ ->
        false
    end
  end
end
