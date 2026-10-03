defmodule Dawarich.A12eCorpus do
  @moduledoc false

  alias Dawarich.{CLI, ScratchRepo, Storage, Wave6Fixtures}
  alias Dawarich.RawData.ArchiveFormat

  @path Path.expand("../fixtures/a12e/cli.json", __DIR__)
  @phrase "phoenix-a12e-archive-phrase-not-for-production"
  @renamed [
    {"rake points:raw_data:verify", "dawarich raw-data verify"},
    {"rake points:raw_data:clear_verified", "dawarich raw-data clear-verified"},
    {"rake points:raw_data:status", "dawarich raw-data status"}
  ]
  @truncate "TRUNCATE users, points, points_raw_data_archives, active_storage_attachments, active_storage_blobs, job_outbox RESTART IDENTITY CASCADE"

  def path, do: @path
  def corpus, do: @path |> File.read!() |> Jason.decode!(floats: :decimals)
  def cases, do: corpus()["cases"]

  def case!(name),
    do: Enum.find(cases(), &(&1["name"] == name)) || raise("no corpus case #{name}")

  def expected_stdout(%{"stdout" => stdout}),
    do:
      Enum.reduce(@renamed, stdout, fn {rails, phoenix}, acc ->
        String.replace(acc, rails, phoenix)
      end)

  def expected_checks(%{"after" => checks}),
    do: Map.new(checks, fn {label, %{"json" => json}} -> {label, json} end)

  def stderr_message(stderr), do: String.replace(stderr, ~r/^dawarich: /m, "")

  def replay(%{"seed" => seed} = c, extra \\ %{}) do
    storage = Wave6Fixtures.local_storage!()
    load!(seed, storage)
    {:ok, out} = StringIO.open("")
    {:ok, err} = StringIO.open("")
    {:ok, stdin} = StringIO.open(c["stdin"] || "")

    base = %{
      repo: ScratchRepo,
      out: out,
      err: err,
      stdin: stdin,
      env: Map.merge(%{"SELF_HOSTED" => "true"}, c["env"]),
      storage: storage,
      archive_key: ArchiveFormat.key(%{"ARCHIVE_ENCRYPTION_KEY" => @phrase})
    }

    ctx = Map.merge(base, extra)

    within_drops(c["drop"], fn ->
      code = CLI.run(c["argv"], ctx)
      checks = Map.new(c["after"], fn {label, %{"sql" => sql}} -> {label, json(sql)} end)
      %{exit: code, stdout: text(out), stderr: text(err), checks: checks}
    end)
  end

  def json(sql) do
    [[text]] =
      ScratchRepo.query!(
        "SELECT coalesce(json_agg(row_to_json(q)), '[]')::text FROM (#{sql}) q",
        [],
        log: false
      ).rows

    text
  end

  defp text(pid), do: pid |> StringIO.contents() |> elem(1)

  defp within_drops([], fun), do: fun.()

  defp within_drops(tables, fun) do
    {:error, {:replayed, result}} =
      ScratchRepo.transaction(fn ->
        Enum.each(tables, &ScratchRepo.query!("DROP TABLE #{&1} CASCADE", [], log: false))
        ScratchRepo.rollback({:replayed, fun.()})
      end)

    result
  end

  defp load!(%{"tables" => tables, "sequences" => sequences, "objects" => objects}, storage) do
    ScratchRepo.query!(@truncate, [], log: false)
    now = DateTime.utc_now()

    for [table, rows] <- tables, row <- rows do
      ScratchRepo.query!(
        "INSERT INTO #{table} SELECT * FROM jsonb_populate_record(NULL::#{table}, $1::jsonb)",
        [resolve(row, now)],
        log: false
      )
    end

    for table <- sequences do
      ScratchRepo.query!(
        "SELECT setval(pg_get_serial_sequence($1, 'id'), coalesce((SELECT max(id) FROM #{table}), 0) + 1, false)",
        [table],
        log: false
      )
    end

    for {key, content} <- objects do
      path = Storage.disk_path(storage.root, key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Base.decode64!(content))
    end

    :ok
  end

  defp resolve(row, now) do
    Map.new(row, fn
      {column, %{"ago" => seconds}} ->
        {column, now |> DateTime.add(-seconds, :second) |> DateTime.to_iso8601()}

      {column, value} ->
        {column, literal(value)}
    end)
  end

  defp literal(%Decimal{} = number), do: Jason.Fragment.new(Decimal.to_string(number, :normal))
  defp literal(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, literal(v)} end)
  defp literal(list) when is_list(list), do: Enum.map(list, &literal/1)
  defp literal(value), do: value
end
