defmodule Dawarich.UserData.Restore.Tracks do
  @moduledoc false
  alias Dawarich.UserData.Restore.Batch
  alias Dawarich.Imports.Fence
  alias Dawarich.Ingest.Ruby

  @attributes ~w(start_at end_at original_path distance avg_speed duration elevation_gain elevation_loss elevation_max elevation_min dominant_mode)

  def call(repo, user, data, context) when is_list(data) do
    Enum.reduce(data, 0, fn row, count -> count + restore(repo, user, row, context) end)
  end

  def call(_, _, _, _), do: 0

  defp restore(repo, user, row, context) when is_map(row) do
    attrs =
      row
      |> Map.take(@attributes)
      |> Map.merge(%{"user_id" => user, "created_at" => context.now, "updated_at" => context.now})

    cast = Batch.row!(repo, "tracks", attrs, context)

    existing =
      repo.query!(
        "SELECT id,distance FROM tracks WHERE user_id=$1 AND start_at=$2::text::timestamp AND end_at=$3::text::timestamp ORDER BY id LIMIT 1",
        [user, cast["start_at"], cast["end_at"]],
        log: false
      ).rows

    distance = cast["distance"]

    cond do
      not valid?(cast) ->
        0

      match?([[_, ^distance]], existing) ->
        0

      true ->
        Fence.run(context, fn ->
          try do
            write(repo, user, attrs, cast, [], row["segments"], context)
          rescue
            e in Postgrex.Error ->
              if e.postgres[:code] == :unique_violation do
                write(repo, user, attrs, cast, existing, row["segments"], context)
              else
                reraise e, __STACKTRACE__
              end
          end
        end)
    end
  rescue
    e in Dawarich.Imports.LeaseLost -> reraise e, __STACKTRACE__
    _ -> 0
  end

  defp restore(_, _, _, _), do: 0

  defp write(repo, user, attrs, cast, existing, segments, context) do
    {count, id} =
      case existing do
        [] ->
          id = Batch.create_record!(repo, "tracks", attrs, context)
          effect(repo, user, id, cast, :created)
          segments(repo, id, segments, context)
          {1, id}

        [[id, _]] ->
          {:ok, refreshed} =
            repo.transaction(fn ->
              repo.query!("SAVEPOINT restore_track_refresh", [], log: false)

              try do
                Batch.update!(
                  repo,
                  "tracks",
                  id,
                  Map.drop(attrs, ~w(start_at end_at created_at)),
                  context
                )

                if Ruby.present?(segments) do
                  repo.query!("DELETE FROM track_segments WHERE track_id=$1", [id], log: false)
                  segments(repo, id, segments, context)
                end

                effect(repo, user, id, cast, :updated)
                repo.query!("RELEASE SAVEPOINT restore_track_refresh", [], log: false)
                id
              rescue
                e in Dawarich.Imports.LeaseLost ->
                  reraise e, __STACKTRACE__

                _ ->
                  repo.query!("ROLLBACK TO SAVEPOINT restore_track_refresh", [], log: false)
                  repo.query!("RELEASE SAVEPOINT restore_track_refresh", [], log: false)
                  nil
              end
            end)

          {0, refreshed}
      end

    if id, do: Dawarich.Tracks.MapMatching.Enqueuer.call(repo, id)
    count
  end

  defp valid?(row),
    do:
      Enum.all?(~w(start_at end_at original_path), &Ruby.present?(row[&1])) and
        Enum.all?(~w(distance avg_speed duration), &(is_number(row[&1]) and row[&1] >= 0))

  defp segments(repo, id, data, context) when is_list(data) do
    Enum.each(data, fn row ->
      if is_map(row) do
        attrs =
          row
          |> Map.put("track_id", id)
          |> Map.put_new("created_at", context.now)
          |> Map.put_new("updated_at", context.now)

        cast = Batch.row!(repo, "track_segments", attrs, context)
        unless valid_segment?(cast), do: raise(ArgumentError, "Invalid track segment")
        Batch.create!(repo, "track_segments", attrs, context)
      end
    end)
  end

  defp segments(_, _, _, _), do: :ok

  defp valid_segment?(row) do
    indexed =
      row["start_index"] != nil and row["end_index"] != nil and
        row["end_index"] >= row["start_index"]

    timed = row["start_at"] != nil and row["end_at"] != nil and row["end_at"] >= row["start_at"]

    (indexed or timed) and
      Enum.all?(
        ~w(start_index end_index distance duration avg_speed max_speed),
        &(row[&1] == nil or (is_number(row[&1]) and row[&1] >= 0))
      )
  end

  defp effect(repo, user, id, cast, kind) do
    stamps =
      Enum.map(~w(start_at end_at), fn key ->
        NaiveDateTime.from_iso8601!(cast[key])
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix()
      end)

    Dawarich.Tracks.Effects.write!(repo, user, %{kind => [id], :stamps => stamps})
  end
end
