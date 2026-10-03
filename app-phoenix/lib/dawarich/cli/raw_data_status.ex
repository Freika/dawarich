defmodule Dawarich.CLI.RawDataStatus do
  @moduledoc false

  import Dawarich.CLI, only: [lines: 2, rule: 0, fail: 2]

  alias Dawarich.RubyFloat

  @units ~w(Bytes KB MB GB TB PB EB ZB)
  @counts """
  SELECT
    (SELECT count(*) FROM points_raw_data_archives),
    (SELECT count(*) FROM points_raw_data_archives WHERE verified_at IS NOT NULL),
    (SELECT count(*) FROM points),
    (SELECT count(*) FROM points WHERE raw_data_archived = true),
    (SELECT count(*) FROM points WHERE raw_data_archived = true AND raw_data = '{}'::jsonb),
    (SELECT coalesce(sum(b.byte_size), 0)::bigint FROM active_storage_blobs b
       JOIN active_storage_attachments a ON a.blob_id = b.id
       WHERE a.record_type = 'Points::RawDataArchive'),
    (SELECT count(*) FROM points_raw_data_archives WHERE archived_at > now() - interval '7 days')
  """
  @top """
  SELECT u.email, count(*), sum(a.point_count)
  FROM points_raw_data_archives a JOIN users u ON u.id = a.user_id AND u.deleted_at IS NULL
  GROUP BY a.user_id, u.email ORDER BY count(*) DESC, a.user_id LIMIT 10
  """

  def status([], ctx) do
    [[total, verified, points, archived, cleared, bytes, recent]] =
      ctx.repo.query!(@counts, [], log: false).rows

    lines(
      ctx,
      [
        rule(),
        "  Points raw_data Archive Statistics",
        rule(),
        "",
        "Archives: #{total} (#{verified} verified, #{total - verified} unverified)",
        "Points archived: #{archived} / #{points} (#{percentage(archived, points)}%)",
        "Points cleared: #{cleared}",
        "Archived but not cleared: #{archived - cleared}",
        "",
        "Storage used: #{human_size(bytes)}",
        "",
        "Archives created last 7 days: #{recent}",
        "",
        "Top 10 users by archive count:",
        String.duplicate("─", 49)
      ] ++ top(ctx.repo) ++ [""]
    )

    0
  end

  def status(_args, ctx), do: fail(ctx, "usage: dawarich raw-data status")

  def human_size(bytes) when bytes < 1024,
    do: "#{bytes} #{if bytes == 1, do: "Byte", else: "Bytes"}"

  def human_size(bytes) do
    exponent = min(trunc(:math.log(bytes) / :math.log(1024)), length(@units) - 1)
    value = bytes / Integer.pow(1024, exponent)
    "#{significant(value)} #{Enum.at(@units, exponent)}"
  end

  defp significant(value) do
    digits = trunc(Float.floor(:math.log10(value) + 1))

    value
    |> Float.to_string()
    |> Decimal.new()
    |> Decimal.round(3 - digits, :half_up)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp percentage(_archived, 0), do: "0"

  defp percentage(archived, points),
    do: Float.to_string(RubyFloat.round(archived / points * 100, 2))

  defp top(repo) do
    repo.query!(@top, [], log: false).rows
    |> Enum.with_index(1)
    |> Enum.map(fn {[email, archives, points], index} ->
      "#{index}. #{String.pad_trailing(email, 30)} #{String.pad_leading(to_string(archives), 3)} archives, #{String.pad_leading(to_string(points), 8)} points"
    end)
  end
end
