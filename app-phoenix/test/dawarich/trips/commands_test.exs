defmodule Dawarich.Trips.CommandsTest do
  use Dawarich.DataCase, async: true

  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.TripsSeeds
  alias Dawarich.Trips.Commands

  @now ~U[2026-10-03 10:00:00.000000Z]

  setup do
    Ownership.put!(Repo, "command:trips.calculate", :oban)
    :ok
  end

  defp scope(id, attrs \\ %{}) do
    TripsSeeds.user!(id)

    if attrs != %{},
      do: Repo.query!("UPDATE users SET active_until=$2 WHERE id=$1", [id, attrs.active_until])

    Scope.for_user(Accounts.get(id), "en")
  end

  defp trip!(scope, id, attrs \\ %{}),
    do: TripsSeeds.trip!(Map.merge(%{id: id, user_id: scope.user.id}, attrs))

  defp outbox(id),
    do:
      Repo.query!(
        "SELECT count(*) FROM job_outbox WHERE command_type='trips.calculate' AND aggregate_id=$1",
        [id]
      ).rows

  defp body(id),
    do:
      Repo.query!(
        "SELECT body FROM action_text_rich_texts WHERE record_type='Trip' AND record_id=$1",
        [id]
      ).rows

  test "trip duplicate recalculation publishes once within the source cooldown" do
    owner = scope(9_601)
    id = trip!(owner, 960_101)

    assert {:ok, %{status: :queued, notice: queued}} =
             Commands.recalculate(owner, id, @now, repo: Repo)

    assert queued =~ "recalculating_the_page_will_update_automatically"

    assert {:ok, %{status: :cooldown, notice: cooldown}} =
             Commands.recalculate(owner, id, DateTime.add(@now, 30), repo: Repo)

    assert cooldown =~ "already_recalculating"
    assert outbox(id) == [[1]]

    assert {:ok, %{status: :queued}} =
             Commands.recalculate(owner, id, DateTime.add(@now, 61), repo: Repo)
  end

  test "trip write rollback restores description and pending effects" do
    owner = scope(9_602)
    id = trip!(owner, 960_201)
    TripsSeeds.rich_text!(id, "<div>Before</div>")
    Ownership.put!(Repo, "command:trips.calculate", :sidekiq)

    attrs = %{
      "name" => "Renamed",
      "started_at" => "2026-05-01T08:00",
      "ended_at" => "2026-05-03T08:00",
      "description" => "<div>After</div>"
    }

    assert Commands.update(owner, id, attrs, @now, repo: Repo) == {:error, :unavailable}
    assert body(id) == [["<div>Before</div>"]]
    assert Repo.query!("SELECT name FROM trips WHERE id=$1", [id]).rows == [["trip 960201"]]
    assert outbox(id) == [[0]]

    Ownership.put!(Repo, "command:trips.calculate", :oban)
    assert {:ok, %{id: ^id, notice: notice}} = Commands.update(owner, id, attrs, @now, repo: Repo)
    assert notice == "controllers.trips.trip_was_successfully_updated"
    assert body(id) == [["<div>After</div>"]]
    assert outbox(id) == [[1]]
  end

  test "foreign or inactive trip commands fail before effects" do
    owner = scope(9_603)
    stranger = scope(9_604)
    lapsed = scope(9_605, %{active_until: ~N[2026-01-01 00:00:00]})
    id = trip!(owner, 960_301)

    valid = %{
      "name" => "New",
      "started_at" => "2026-05-01T08:00",
      "ended_at" => "2026-05-02T08:00"
    }

    assert Commands.update(stranger, id, %{"name" => "Taken"}, @now, repo: Repo) ==
             {:error, :not_found}

    assert Commands.delete(stranger, id, @now, repo: Repo) == {:error, :not_found}
    assert Commands.recalculate(stranger, id, @now, repo: Repo) == {:error, :not_found}
    assert Commands.request_export(stranger, id, "gpx", repo: Repo) == {:error, :not_found}
    assert Commands.ensure_calculated(stranger, id, @now, repo: Repo) == {:error, :not_found}
    assert Commands.create(lapsed, valid, @now, repo: Repo) == {:error, :inactive}

    assert Commands.recalculate(lapsed, trip!(lapsed, 960_302), @now, repo: Repo) ==
             {:error, :inactive}

    assert Commands.update(owner, "960301x", %{"name" => "x"}, @now, repo: Repo) ==
             {:error, :not_found}

    assert Repo.query!("SELECT name FROM trips WHERE id=$1", [id]).rows == [["trip 960301"]]

    assert Repo.query!("SELECT count(*) FROM trips WHERE user_id=$1", [lapsed.user.id]).rows == [
             [1]
           ]

    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    assert Repo.query!("SELECT count(*) FROM exports").rows == [[0]]
  end

  test "create validates in place, then saves and queues one calculation" do
    owner = scope(9_606)

    assert {:invalid, errors, values} =
             Commands.create(
               owner,
               %{
                 "name" => "",
                 "started_at" => "2026-05-03T08:00",
                 "ended_at" => "2026-05-01T08:00"
               },
               @now, repo: Repo)

    assert {"name", "Name can't be blank"} in errors
    assert Enum.any?(errors, fn {field, _} -> field == "ended_at" end)
    assert values.values["started_at"] == "2026-05-03T08:00"

    assert Repo.query!("SELECT count(*) FROM trips WHERE user_id=$1", [owner.user.id]).rows == [
             [0]
           ]

    assert {:ok, %{id: id, notice: notice}} =
             Commands.create(
               owner,
               %{
                 "name" => "Coast",
                 "started_at" => "2026-05-01T08:00",
                 "ended_at" => "2026-05-02T08:00",
                 "description" => "<div>Hi</div>"
               },
               @now, repo: Repo)

    assert notice =~ "trip_was_successfully_created"
    assert body(id) == [["<div>Hi</div>"]]
    assert outbox(id) == [[1]]
  end

  test "delete, export and the missing-data load command keep their source effects" do
    owner = scope(9_607)
    id = trip!(owner, 960_701, %{distance: nil})

    assert Commands.request_export(owner, id, "kml", repo: Repo) == {:error, :invalid_format}
    assert {:ok, %{notice: export}} = Commands.request_export(owner, id, "gpx", repo: Repo)
    assert export =~ "trip_export_initiated"

    assert Repo.query!("SELECT name FROM exports WHERE user_id=$1", [owner.user.id]).rows == [
             ["trip_trip-960701_2026-05-09.gpx"]
           ]

    assert Commands.ensure_calculated(owner, id, @now, repo: Repo) == {:ok, :queued}
    assert Commands.ensure_calculated(owner, id, @now, repo: Repo) == {:ok, :pending}
    assert outbox(id) == [[1]]

    ready = trip!(owner, 960_702, %{path: [[1, 2], [3, 4]]})
    assert Commands.ensure_calculated(owner, ready, @now, repo: Repo) == {:ok, :ready}

    assert {:ok, %{notice: "controllers.trips.trip_was_successfully_destroyed"}} =
             Commands.delete(owner, id, @now, repo: Repo)

    assert Repo.query!("SELECT count(*) FROM trips WHERE id=$1", [id]).rows == [[0]]
  end
end
