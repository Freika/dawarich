defmodule Dawarich.UserData.Restore.Trips do
  @moduledoc false
  alias Dawarich.UserData.Restore.Batch
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Imports.{Fence, Trek.Itinerary}

  @attributes ~w(name started_at ended_at distance path visited_countries source_identifier source_digest source_synced_at source_snapshot)

  def call(repo, user, data, context) when is_list(data) do
    existing =
      repo.query!(
        "SELECT name,to_char(started_at,'YYYY-MM-DD\"T\"HH24:MI:SS'),to_char(ended_at,'YYYY-MM-DD\"T\"HH24:MI:SS') FROM trips WHERE user_id=$1",
        [user],
        log: false
      ).rows
      |> MapSet.new()

    prepared =
      data
      |> Enum.filter(&valid?/1)
      |> Enum.map(fn row ->
        row =
          row
          |> Map.take(@attributes)
          |> Map.merge(%{
            "user_id" => user,
            "created_at" => context.now,
            "updated_at" => context.now
          })

        status =
          if Ruby.present?(row["source_identifier"]) or Ruby.present?(row["source_snapshot"]),
            do: "stopped"

        Map.put(row, "source_status", status)
      end)
      |> Enum.reject(fn row ->
        MapSet.member?(existing, [
          row["name"],
          normalize(row["started_at"], context),
          normalize(row["ended_at"], context)
        ])
      end)

    {planned, ordinary} = Enum.split_with(prepared, &Ruby.present?(&1["source_snapshot"]))

    Batch.write(repo, "trips", ordinary, context) +
      Enum.reduce(planned, 0, fn row, total -> total + planned(repo, row, context) end)
  end

  def call(_, _, _, _), do: 0

  defp valid?(row) when is_map(row),
    do: Enum.all?(~w(name started_at ended_at), &Ruby.present?(row[&1]))

  defp valid?(_), do: false

  defp normalize(value, context) do
    row = Batch.row!(context.repo, "trips", %{"started_at" => value}, context)

    case row["started_at"] do
      nil -> value
      time -> String.slice(time, 0, 19)
    end
  end

  defp planned(repo, row, context) do
    Fence.run(context, fn ->
      {:ok, count} =
        repo.transaction(fn ->
          repo.query!("SAVEPOINT restore_planned_trip", [], log: false)

          try do
            cast = Batch.row!(repo, "trips", row, context)

            if is_nil(cast["started_at"]) or is_nil(cast["ended_at"]) or
                 cast["started_at"] >= cast["ended_at"],
               do: raise(ArgumentError, "Invalid planned trip dates")

            id = Batch.create_record!(repo, "trips", row, context)
            ctx = %{context | now: DateTime.from_naive!(context.now, "Etc/UTC")}
            Itinerary.replace!(ctx, id, row["source_snapshot"])
            repo.query!("RELEASE SAVEPOINT restore_planned_trip", [], log: false)
            1
          rescue
            _ ->
              repo.query!("ROLLBACK TO SAVEPOINT restore_planned_trip", [], log: false)
              repo.query!("RELEASE SAVEPOINT restore_planned_trip", [], log: false)
              0
          end
        end)

      count
    end)
  end
end
