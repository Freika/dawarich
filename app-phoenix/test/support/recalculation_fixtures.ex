defmodule Dawarich.RecalculationFixtures do
  @moduledoc false

  @path Path.expand("../fixtures/a12d1b3/recalculations.json", __DIR__)
  @tables ~w(users imports tracks track_segments points stats digests active_storage_blobs active_storage_attachments)

  def corpus, do: @path |> File.read!() |> Jason.decode!()
  def all, do: corpus()["cases"]

  def case!(id),
    do: Enum.find(all(), &(&1["id"] == id)) || raise(ArgumentError, "no recalculation case #{id}")

  def load!(repo, %{"input" => input}) do
    for table <- @tables, row <- input[table] || [], do: row!(repo, table, row)
    :ok
  end

  def row!(repo, table, row) when table in @tables do
    columns = row |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &~s("#{&1}"))

    repo.query!(
      "INSERT INTO public.#{table} (#{columns}) SELECT #{columns} " <>
        "FROM json_populate_record(NULL::public.#{table}, $1::text::json)",
      [Jason.encode!(row)],
      log: false
    )

    :ok
  end
end
