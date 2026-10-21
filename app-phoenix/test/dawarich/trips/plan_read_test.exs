defmodule Dawarich.Trips.PlanReadTest do
  use Dawarich.IngestCase, async: true
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  alias Dawarich.Trips.{PlanRead, PlanGeojson}

  @entry File.read!("test/fixtures/trips/remaining/effects.json")
         |> Jason.decode!()
         |> Map.fetch!("effects")
         |> Enum.find(&(&1["name"] == "plan_future_show"))
  @tables ~w(planned_days planned_stops planned_day_notes planned_reservations planned_accommodations planned_travellers planned_unplanned_places)

  defmodule ReadRepo do
    def query!(sql, params, opts \\ []) do
      unless String.starts_with?(String.trim(sql), "SELECT"), do: raise("plan read wrote SQL")

      if Process.get(:skip_plan_preflight, false) and
           String.starts_with?(String.trim(sql), "SELECT NOT EXISTS"),
         do: %{rows: [[true]]},
         else: Dawarich.Repo.query!(sql, params, opts)
    end
  end

  defp value(key, raw) do
    cond do
      is_nil(raw) ->
        nil

      key in ~w(latitude longitude) ->
        Decimal.new(raw)

      key in ~w(date starts_on ends_on) ->
        Date.from_iso8601!(raw)

      key in ~w(created_at updated_at starts_at ends_at) and String.contains?(raw, "T") ->
        raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

      true ->
        raw
    end
  end

  test "mixed owner plan associations stay on Rails without exposing foreign data" do
    user = TripsSeeds.user!(8981)
    foreign = TripsSeeds.user!(8982)
    stamp = ~N[2026-10-03 08:00:00.000000]
    id = TripsSeeds.trip!(%{id: 898_101, user_id: user.id})
    other = TripsSeeds.trip!(%{id: 898_201, user_id: foreign.id})

    Repo.insert_all("trip_sources", [
      %{
        id: id,
        user_id: foreign.id,
        provider: "trek",
        base_url: "https://foreign.example.invalid",
        status: 0,
        created_at: stamp,
        updated_at: stamp
      }
    ])

    Repo.query!("UPDATE trips SET trip_source_id=$2 WHERE id=$1", [id, id])

    for association <- [:source, :reservation, :day] do
      if association != :source do
        Repo.query!("UPDATE trips SET trip_source_id=NULL WHERE id=$1", [id])
        Repo.query!("DELETE FROM planned_reservations")
        Repo.query!("DELETE FROM planned_days")
        day_trip = if association == :reservation, do: id, else: other
        reservation_trip = if association == :reservation, do: other, else: id

        Repo.insert_all("planned_days", [
          %{
            id: id,
            trip_id: day_trip,
            date: ~D[2026-10-03],
            position: 1,
            created_at: stamp,
            updated_at: stamp
          }
        ])

        Repo.insert_all("planned_reservations", [
          %{
            id: id,
            trip_id: reservation_trip,
            planned_day_id: id,
            title: "Foreign reservation",
            created_at: stamp,
            updated_at: stamp
          }
        ])
      end

      assert :rails == PlanRead.load(ReadRepo, user.id, id), to_string(association)
      assert :rails == Dawarich.TripPage.gate(user, id), to_string(association)
      assert :rails == Dawarich.TripList.gate(user, 1), to_string(association)
      assert :rails == Dawarich.TripList.load(user, 1), to_string(association)
      assert {:replay, _} = Dawarich.Trips.WebForm.load(ReadRepo, user, id, %{})
      Process.put(:skip_plan_preflight, true)
      assert {:ok, scoped} = PlanRead.load(ReadRepo, user.id, id)
      if association == :source, do: assert(scoped.source == nil)

      if association == :reservation do
        assert scoped.reservations == []
        assert Enum.all?(scoped.days, &(&1.reservations == []))
      end

      Process.delete(:skip_plan_preflight)
      assert commands() == []
      assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    end
  end

  test "plans preserve association ordering numbering and coordinates" do
    actor = @entry["before"]["actor"]

    RailsUser.insert!(%{
      id: actor["id"],
      email: "a8-plan@example.invalid",
      api_key: "a8-plan",
      settings: actor["settings"]
    })

    [trip] = @entry["before"]["trips"]
    [source] = @entry["before"]["trip_sources"]
    stamp = ~N[2026-10-03 08:00:00.000000]

    Repo.insert_all("trip_sources", [
      %{
        id: source["id"],
        user_id: actor["id"],
        provider: source["provider"],
        base_url: source["base_url"],
        status: 0,
        importing: false,
        created_at: stamp,
        updated_at: stamp
      }
    ])

    TripsSeeds.trip!(%{
      id: trip["id"],
      user_id: actor["id"],
      path: nil,
      source_identifier: trip["source_identifier"],
      source_status: 0,
      trip_source_id: source["id"],
      source_synced_at: stamp
    })

    for table <- @tables do
      rows =
        for row <- @entry["before"][table],
            do: Map.new(row, fn {key, raw} -> {key, value(key, raw)} end)

      Repo.insert_all(table, rows)
    end

    assert {:ok, plan} = PlanRead.load(ReadRepo, actor["id"], trip["id"])
    assert :not_found == PlanRead.load(ReadRepo, actor["id"] + 1, trip["id"])
    assert :not_found == PlanRead.load(ReadRepo, actor["id"], trip["id"] + 999)
    assert Enum.map(plan.days, & &1.date) == [~D[2026-10-03], ~D[2026-10-04]]
    [first, second] = plan.days
    assert first.position == 2
    assert Enum.map(first.stops, & &1.name) == ~w(Unlocated Auensee Rosental Zero)
    assert [%{body: "Source detail", position: 1}] = first.day_notes
    assert [%{title: "Train <&>"}] = first.reservations
    assert second.stops == []

    assert [%{title: "Loose reservation"}] =
             Enum.filter(plan.reservations, &is_nil(&1.planned_day_id))

    assert [%{name: "Traveller <&>"}] = plan.travellers
    assert plan.source.base_url == source["base_url"]
    refute Map.has_key?(plan.source, :api_key)
    refute Map.has_key?(plan.source, :selection_token)

    golden =
      File.read!("test/fixtures/trips/remaining/pages/plan_future_show.html")
      |> LazyHTML.from_document()
      |> LazyHTML.query("[data-trip-maplibre-preview-plan-value]")
      |> LazyHTML.attribute("data-trip-maplibre-preview-plan-value")
      |> hd()
      |> Jason.decode!()

    assert PlanGeojson.build(plan) == golden

    assert [
             %{
               "properties" => %{"number" => 2},
               "geometry" => %{"coordinates" => [12.3712, 51.3391]}
             }
             | _
           ] = golden["features"]

    assert Enum.map(golden["features"], & &1["properties"]["kind"]) ==
             ~w(stop stop stop route stay unplanned)

    assert Enum.at(golden["features"], 2)["geometry"]["coordinates"] == [0.0, 0.0]
    assert nil == PlanGeojson.build(%{plan | days: [], accommodations: [], unplanned_places: []})

    one = %{
      plan
      | days: [%{first | stops: Enum.take(first.stops, 2)}],
        accommodations: [],
        unplanned_places: []
    }

    assert [%{"properties" => %{"number" => 2}}] = PlanGeojson.build(one)["features"]
    assert PlanGeojson.build(%{one | days: [second]}) == nil
    assert commands() == []
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
  end
end
