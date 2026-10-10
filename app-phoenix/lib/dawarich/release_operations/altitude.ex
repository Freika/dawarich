defmodule Dawarich.ReleaseOperations.Altitude do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  require Logger

  alias Dawarich.RawData.{ArchiveFormat, Archives}
  alias Dawarich.{ReleaseOperations, RubyDecimal, Storage}
  alias Dawarich.ReleaseOperations.AltitudeExtractor

  @batch 1_000
  @users "SELECT id FROM users WHERE deleted_at IS NULL AND points_count > 0 AND id > $1 ORDER BY id LIMIT 1000"
  @raw """
  SELECT id, altitude, raw_data FROM points
  WHERE user_id = $1 AND raw_data <> '{}'::jsonb AND id > $2
  ORDER BY id LIMIT 1000
  """
  @archive "SELECT id, metadata FROM points_raw_data_archives WHERE user_id = $1 AND id > $2 ORDER BY id LIMIT 1"
  @existing "SELECT id, altitude FROM points WHERE id = ANY($1)"
  @update """
  UPDATE points p
  SET altitude = v.altitude,
      altitude_decimal = v.altitude_decimal,
      updated_at = CASE
        WHEN p.altitude IS NOT DISTINCT FROM v.altitude AND p.altitude_decimal IS NOT DISTINCT FROM v.altitude_decimal
        THEN p.updated_at ELSE now() END
  FROM unnest($1::bigint[], $2::int[], $3::numeric[]) AS v(id, altitude, altitude_decimal)
  WHERE p.id = v.id
  """

  def command_type, do: "release.altitude"

  def args_from_command(1, payload) when map_size(payload) == 0,
    do: {:ok, %{"version" => 1, "cursor" => %{"phase" => "users", "after_id" => 0}}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(job), do: ReleaseOperations.run(Dawarich.Jobs.repo(), Oban, __MODULE__, job)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def step(repo, %{cursor: %{"phase" => "users", "after_id" => after_id}} = op) do
    ReleaseOperations.commit(repo, op, fn ->
      ids = ReleaseOperations.ids(repo, @users, [after_id])

      Enum.each(
        ids,
        &ReleaseOperations.spawn!(op, %{"phase" => "raw", "user_id" => &1, "after_id" => 0})
      )

      if length(ids) < @batch,
        do: :done,
        else: {%{"phase" => "users", "after_id" => List.last(ids)}, 0}
    end)
  end

  def step(
        repo,
        %{cursor: %{"phase" => "raw", "user_id" => user_id, "after_id" => after_id}} = op
      ) do
    rows = repo.query!(@raw, [user_id, after_id], log: false).rows

    updates =
      for [id, current, raw] <- rows,
          altitude = AltitudeExtractor.from_raw_data(raw),
          altitude != nil and current != altitude,
          do: {id, altitude}

    ReleaseOperations.commit(repo, op, fn ->
      write!(repo, updates)

      case rows do
        [] -> {%{"phase" => "archives", "user_id" => user_id, "after_id" => 0}, 0}
        _ -> {%{op.cursor | "after_id" => rows |> List.last() |> hd()}, 0}
      end
    end)
  end

  def step(
        repo,
        %{cursor: %{"phase" => "archives", "user_id" => user_id, "after_id" => after_id}} = op
      ) do
    case repo.query!(@archive, [user_id, after_id], log: false).rows do
      [] ->
        ReleaseOperations.commit(repo, op, fn -> :done end)

      [[archive_id, metadata]] ->
        updates = archive_updates(repo, op.opts, archive_id, metadata)

        ReleaseOperations.commit(repo, op, fn ->
          updates |> Enum.chunk_every(@batch) |> Enum.each(&write_existing!(repo, &1))
          {%{op.cursor | "after_id" => archive_id}, 0}
        end)
    end
  end

  defp archive_updates(repo, opts, archive_id, metadata) do
    storage = Keyword.get_lazy(opts, :storage, fn -> Storage.config!(System.get_env()) end)
    key = Keyword.get_lazy(opts, :archive_key, &ArchiveFormat.key/0)

    case Archives.file_key(repo, archive_id) do
      {:error, :file_not_attached} ->
        []

      {:ok, blob_key} ->
        {:ok, gzip} = storage |> Storage.get!(blob_key) |> ArchiveFormat.decode(metadata, key)

        for line <- ArchiveFormat.lines(gzip),
            data = Jason.decode!(line),
            altitude = AltitudeExtractor.from_raw_data(data["raw_data"]),
            altitude != nil,
            do: {data["id"], altitude}
    end
  rescue
    error ->
      Logger.error("Failed to process archive #{archive_id}: #{Exception.message(error)}")
      []
  end

  defp write_existing!(repo, updates) do
    current =
      Map.new(repo.query!(@existing, [Enum.map(updates, &elem(&1, 0))], log: false).rows, fn [
                                                                                               id,
                                                                                               altitude
                                                                                             ] ->
        {id, altitude}
      end)

    write!(
      repo,
      for(
        {id, altitude} <- updates,
        Map.has_key?(current, id),
        current[id] != altitude,
        do: {id, altitude}
      )
    )
  end

  defp write!(_repo, []), do: :ok

  defp write!(repo, updates) do
    {ids, altitudes} = Enum.unzip(updates)
    decimals = Enum.map(altitudes, &Decimal.new(RubyDecimal.column(&1, 10, 2)))
    repo.query!(@update, [ids, Enum.map(altitudes, &trunc/1), decimals], log: false)
  end
end
