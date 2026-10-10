defmodule Dawarich.Trips.WebDeleteTest do
  use Dawarich.IngestCase, async: true
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  alias Dawarich.Trips.WebDelete

  @effects "test/fixtures/trips/remaining/effects.json"
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @entry Enum.find(@effects, &(&1["name"] == "destroy_ordinary_oban"))
  @stamp ~N[2026-10-03 08:00:00.000000]
  @tables ~w(trip_sources trips planned_days planned_stops planned_day_notes planned_reservations planned_accommodations planned_travellers planned_unplanned_places notes exports route_videos posters action_text_rich_texts shared_links points)
  @dependent ~w(planned_days planned_stops planned_day_notes planned_reservations planned_accommodations planned_travellers planned_unplanned_places notes action_text_rich_texts trips)

  defp value("shared_links", "id", value), do: Ecto.UUID.dump!(value)
  defp value("shared_links", "resource_type", value), do: %{"trip" => 0, "track" => 1}[value]
  defp value("exports", "file_type", "points"), do: 0
  defp value("exports", "file_format", "json"), do: 0
  defp value("route_videos", "status", "expired"), do: 1
  defp value(table, "status", "created") when table in ~w(exports posters), do: 0
  defp value("trip_sources", "status", "active"), do: 0
  defp value("trips", "source_status", "active"), do: 0
  defp value(_table, _key, nil), do: nil
  defp value(_table, key, raw) when key in ~w(latitude longitude), do: Decimal.new(raw)
  defp value(_table, key, raw) when key in ~w(date starts_on ends_on), do: Date.from_iso8601!(raw)

  defp value(_table, _key, raw) when is_binary(raw) do
    if String.ends_with?(raw, ".000000Z"),
      do: raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive(),
      else: raw
  end

  defp value(_table, _key, raw), do: raw

  defp seed do
    actor = @entry["before"]["actor"]

    user =
      RailsUser.insert!(%{
        id: actor["id"],
        email: "a8-delete@example.invalid",
        settings: actor["settings"]
      })

    for table <- @tables -- ["points"], raw <- @entry["before"][table] do
      attrs =
        raw
        |> Map.drop(~w(path lonlat))
        |> Map.new(fn {key, raw} -> {String.to_atom(key), value(table, key, raw)} end)

      Repo.insert_all(table, [Map.merge(%{created_at: @stamp, updated_at: @stamp}, attrs)])
    end

    for point <- @entry["before"]["points"] do
      TripsSeeds.point!(%{
        id: point["id"],
        user_id: point["user_id"],
        timestamp: point["timestamp"],
        at: point["lonlat"]
      })

      Repo.query!("UPDATE points SET created_at = $2, updated_at = $2 WHERE id = $1", [
        point["id"],
        @stamp
      ])
    end

    user
  end

  defp graph do
    Map.new(@tables, fn table ->
      {table, Repo.query!("SELECT to_jsonb(t) FROM #{table} t ORDER BY id").rows}
    end)
  end

  test "trip deletion retains mixed owner reservations without nullifying them" do
    user = seed()
    foreign = TripsSeeds.user!(8982)
    id = hd(@entry["before"]["trips"])["id"]
    TripsSeeds.trip!(%{id: id + 100, user_id: foreign.id})

    Repo.insert_all("planned_reservations", [
      %{
        id: id + 100,
        trip_id: id + 100,
        planned_day_id: id,
        title: "Foreign reservation",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    before = graph()
    assert {:replay, _} = WebDelete.run(Repo, user, id, %{})
    assert graph() == before
    Repo.query!("UPDATE trips SET user_id=$2 WHERE id=$1", [id + 100, user.id])
    assert {:ok, :deleted} = WebDelete.run(Repo, user, id, %{})

    assert Repo.query!("SELECT planned_day_id FROM planned_reservations WHERE id=$1", [id + 100]).rows ==
             [[nil]]
  end

  test "trip deletion removes supported graph and preserves other owners" do
    user = seed()
    id = hd(@entry["before"]["trips"])["id"]
    before = graph()
    assert {:error, :not_found} = WebDelete.run(Repo, %{id: user.id + 1}, id, %{})
    assert {:error, :not_found} = WebDelete.run(Repo, user, id + 99, %{})
    assert graph() == before

    Repo.insert_all("trips", [
      %{
        id: id + 100,
        user_id: user.id,
        name: "Other trip",
        started_at: @stamp,
        ended_at: NaiveDateTime.add(@stamp, 3600),
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    Repo.insert_all("planned_reservations", [
      %{
        id: id + 100,
        trip_id: id + 100,
        planned_day_id: id,
        title: "Other trip reservation",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    before = graph()
    assert {:ok, :deleted} = WebDelete.run(Repo, user, id, %{})
    after_graph = graph()

    for table <- @dependent do
      assert Enum.all?(after_graph[table], fn [row] -> row["id"] == id + 100 end), table
    end

    assert Repo.query!(
             "SELECT planned_day_id, updated_at FROM planned_reservations WHERE id = $1",
             [id + 100]
           ).rows == [[nil, @stamp]]

    for table <- ~w(trip_sources points exports route_videos posters),
        do: assert(after_graph[table] == before[table], table)

    [[remaining_link]] = after_graph["shared_links"]
    assert remaining_link["resource_type"] == 1
    assert [remaining_link] in before["shared_links"]
    assert @entry["after"]["notes"] == []
    assert @entry["after"]["planned_day_notes"] == []
    assert @entry["after"]["shared_links"] |> Enum.map(& &1["resource_type"]) == ["track"]
    assert commands() == []
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]

    rich_id = id + 100

    Repo.insert_all("action_text_rich_texts", [
      %{
        id: rich_id,
        record_type: "Trip",
        record_id: id + 100,
        name: "description",
        body: "<action-text-attachment></action-text-attachment>",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    assert {:ok, :deleted} = WebDelete.run(Repo, user, id + 100, %{})
    assert Repo.query!("SELECT id FROM action_text_rich_texts WHERE id=$1", [rich_id]).rows == []
  end
end
