defmodule Dawarich.DigestFixtures do
  @moduledoc false

  @path Path.expand("../fixtures/a12d1b1/digests.json", __DIR__)
  @tables ~w(users families family_memberships stats tracks track_segments points digests)

  def all, do: @path |> File.read!() |> Jason.decode!() |> Map.fetch!("cases")

  def case!(id),
    do: Enum.find(all(), &(&1["id"] == id)) || raise(ArgumentError, "no digest corpus case #{id}")

  def load_scheduler!(repo, kase) do
    for table <- ~w(users stats) do
      rows = kase[table]
      columns = columns(hd(rows))

      repo.query!(
        "INSERT INTO public.#{table} (#{columns}) SELECT #{columns} " <>
          "FROM json_populate_recordset(NULL::public.#{table}, $1::text::json)",
        [Jason.encode!(rows)],
        log: false
      )
    end

    :ok
  end

  def load!(repo, kase) do
    if kase["legacy_duplicates"] or kase["null_segment_mode"] do
      unless repo.in_transaction?(),
        do: raise(ArgumentError, "legacy fixtures need a transaction")
    end

    if kase["legacy_duplicates"] do
      repo.query!("DROP INDEX public.index_digests_on_user_year_period_type_monthless")
    end

    if kase["null_segment_mode"] do
      repo.query!(
        "ALTER TABLE public.track_segments ALTER COLUMN transportation_mode DROP NOT NULL"
      )
    end

    for table <- @tables, row <- kase["input"][table] || [], do: row!(repo, table, row)
    :ok
  end

  def row!(repo, table, row) when table in @tables do
    columns = columns(row)

    repo.query!(
      "INSERT INTO public.#{table} (#{columns}) SELECT #{columns} " <>
        "FROM json_populate_record(NULL::public.#{table}, $1::text::json)",
      [Jason.encode!(row)],
      log: false
    )

    :ok
  end

  def project(repo, table, row) when table in @tables do
    %{rows: [[json]]} =
      repo.query!(
        "SELECT row_to_json(x)::text FROM " <>
          "(SELECT #{columns(row)} FROM public.#{table} WHERE id = $1) x",
        [row["id"]],
        log: false
      )

    Jason.decode!(json)
  end

  def digests(repo, user_id) do
    repo.query!(
      "SELECT row_to_json(x)::text FROM " <>
        "(SELECT * FROM public.digests WHERE user_id = $1 ORDER BY id) x",
      [user_id],
      log: false
    ).rows
    |> Enum.map(fn [json] -> Jason.decode!(json) end)
  end

  def options(kase) do
    options = kase["options"]
    {:ok, now, 0} = DateTime.from_iso8601(options["now"])

    ambient =
      if Map.has_key?(options, "ambient_zone"),
        do: [ambient_zone: options["ambient_zone"]],
        else: []

    [now: now, env: options["env"], uuid: options["uuid"]] ++ ambient
  end

  defp columns(row), do: row |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &~s("#{&1}"))
end
