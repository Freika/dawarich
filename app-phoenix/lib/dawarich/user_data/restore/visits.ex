defmodule Dawarich.UserData.Restore.Visits do
  @moduledoc false
  alias Dawarich.UserData.Restore.{Batch, Places}
  alias Dawarich.Imports.Fence
  alias Dawarich.Ingest.Ruby

  def call(repo, user, data, context) when is_list(data) do
    Enum.reduce(data, 0, fn row, count -> count + restore(repo, user, row, context) end)
  end

  def call(_, _, _, _), do: 0

  defp restore(repo, user, row, context) when is_map(row) do
    dates = Batch.row!(repo, "visits", Map.take(row, ~w(name started_at ended_at)), context)

    found =
      repo.query!(
        "SELECT id FROM visits WHERE user_id=$1 AND name IS NOT DISTINCT FROM $2 AND started_at IS NOT DISTINCT FROM $3::text::timestamp AND ended_at IS NOT DISTINCT FROM $4::text::timestamp LIMIT 1",
        [user, dates["name"], dates["started_at"], dates["ended_at"]],
        log: false
      ).rows

    if found != [] do
      0
    else
      Fence.run(context, fn ->
        try do
          place = place(repo, user, row["place_reference"], context)
          attrs = row |> Map.delete("place_reference") |> Map.put("user_id", user)
          attrs = if place, do: Map.put(attrs, "place_id", place), else: attrs
          attrs = owned_refs(repo, user, attrs)

          attrs =
            Enum.reduce(~w(created_at updated_at), attrs, fn key, acc ->
              if Ruby.blank?(acc[key]), do: Map.put(acc, key, context.now), else: acc
            end)

          cast = Batch.row!(repo, "visits", attrs, context)

          if valid?(cast) do
            {:ok, count} =
              repo.transaction(fn ->
                repo.query!("SAVEPOINT restore_visit", [], log: false)

                try do
                  id = Batch.create_record!(repo, "visits", attrs, context)

                  [[stamp]] =
                    repo.query!("SELECT started_at FROM visits WHERE id=$1", [id], log: false).rows

                  Dawarich.Visits.Calendar.changed(
                    repo,
                    user,
                    [DateTime.from_naive!(stamp, "Etc/UTC")],
                    native_owner: Map.get(context, :native_owner, false)
                  )

                  repo.query!("RELEASE SAVEPOINT restore_visit", [], log: false)
                  id && 1
                rescue
                  _ ->
                    repo.query!("ROLLBACK TO SAVEPOINT restore_visit", [], log: false)
                    repo.query!("RELEASE SAVEPOINT restore_visit", [], log: false)
                    0
                end
              end)

            count
          else
            0
          end
        rescue
          e in Dawarich.Imports.LeaseLost -> reraise e, __STACKTRACE__
          _ -> 0
        end
      end)
    end
  end

  defp restore(_, _, _, _), do: 0

  defp valid?(row) do
    Enum.all?(~w(name started_at ended_at duration), &Ruby.present?(row[&1])) and
      row["ended_at"] > row["started_at"] and
      (row["confidence"] == nil or row["confidence"] in 0..100)
  end

  defp place(repo, user, ref, context) when is_map(ref) do
    with true <- Ruby.present?(ref["name"]), {lat, lon} <- Places.coordinates(ref) do
      found = Places.find(repo, user, ref["name"], lat, lon)

      found =
        if found == [],
          do:
            repo.query!(
              "SELECT id FROM places WHERE user_id=$1 AND latitude BETWEEN $2 AND $3 AND longitude BETWEEN $4 AND $5 ORDER BY id LIMIT 1",
              [
                user,
                Decimal.from_float(lat - 0.0001),
                Decimal.from_float(lat + 0.0001),
                Decimal.from_float(lon - 0.0001),
                Decimal.from_float(lon + 0.0001)
              ],
              log: false
            ).rows,
          else: found

      case found do
        [[id]] ->
          id

        [] ->
          Places.call(repo, user, [Map.take(ref, ~w(name latitude longitude source))], context)

          case Places.find(repo, user, ref["name"], lat, lon) do
            [[id]] -> id
            _ -> nil
          end
      end
    else
      _ -> nil
    end
  end

  defp place(_, _, _, _), do: nil

  defp owned_refs(repo, user, attrs) do
    Enum.reduce(
      [{"area_id", "areas"}, {"place_id", "places"}, {"import_id", "imports"}],
      attrs,
      fn {key, table}, acc ->
        if acc[key] &&
             repo.query!(
               "SELECT id FROM #{table} WHERE id=$1 AND user_id=$2",
               [Ruby.to_i(acc[key]), user],
               log: false
             ).rows == [],
           do: Map.put(acc, key, nil),
           else: acc
      end
    )
  end
end
