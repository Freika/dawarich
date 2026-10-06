defmodule DawarichWeb.A12f3bN07Test do
  use Dawarich.DataCase, async: false
  alias Dawarich.{Accounts, DemoData.Importer}
  alias Dawarich.Test.{DemoData, RailsUser}

  setup do
    RailsUser.insert!(%{
      id: 73701,
      email: "demo-n07@test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    RailsUser.insert!(%{id: 73702, email: "demo-foreign@test"})
    :ok
  end

  @tag a12f3b_case: "N07a"
  test "demo import creates marker shifted points and tracks idempotently" do
    Repo.query!(
      "INSERT INTO countries(name,iso_a2,iso_a3,geom,created_at,updated_at) VALUES ('Synthetic','XS','XSS',ST_GeomFromText('MULTIPOLYGON(((13 52,14 52,14 53,13 53,13 52)))',4326),now(),now())",
      [],
      log: false
    )

    user = Accounts.get(73701)
    assert Importer.call(Repo, user, DemoData.fixtures()) == :created

    assert rows("SELECT demo,source,status,name FROM imports WHERE user_id=$1", [user.id]) == [
             [true, 6, 2, "Demo Data (Berlin + Prague)"]
           ]

    assert rows("SELECT min(timestamp),max(timestamp) FROM points WHERE user_id=$1", [user.id]) ==
             [[1_774_735_200, 1_774_735_320]]

    assert rows("SELECT count(country_id),count(*) FROM points WHERE user_id=$1", [user.id]) == [
             [2, 3]
           ]

    assert rows(
             "SELECT altitude,velocity,accuracy,vertical_accuracy,battery,battery_status FROM points WHERE user_id=$1 ORDER BY timestamp LIMIT 1",
             [user.id]
           ) == [[42, "5", 10, 12, 90, 1]]

    assert rows(
             "SELECT distance,duration,dominant_mode,ST_NPoints(original_path) FROM tracks WHERE user_id=$1",
             [user.id]
           ) == [[1000, 600, 2, 2]]

    assert rows("SELECT transportation_mode,confidence,end_index FROM track_segments") == [
             [2, 2, 1]
           ]

    assert rows("SELECT count(track_id) FROM points WHERE user_id=$1", [user.id]) == [[3]]
    assert Importer.call(Repo, user, DemoData.fixtures()) == :exists
    assert rows("SELECT count(*) FROM tracks WHERE user_id=$1", [user.id]) == [[1]]

    bad =
      Keyword.update!(
        DemoData.fixtures(),
        :derivatives,
        &put_in(&1, ["tracks", Access.at(0), "mode"], "invalid")
      )

    assert Importer.call(Repo, Accounts.get(73702), bad) == :error
    assert rows("SELECT count(*) FROM imports WHERE user_id=73702") == [[0]]
    assert rows("SELECT count(*) FROM points WHERE user_id=73702") == [[0]]
  end

  @tag a12f3b_case: "N07b"
  test "demo import never appends duplicate tracks after retry" do
    live = DemoData.real_point(73701, 1_774_735_200)
    foreign = DemoData.real_point(73702, 1_774_735_200)
    user = Accounts.get(73701)
    assert Importer.call(Repo, user, DemoData.fixtures()) == :created

    before =
      rows("SELECT id,import_id,track_id FROM points WHERE import_id IS NOT NULL ORDER BY id")

    tracks = rows("SELECT id FROM tracks ORDER BY id")
    assert Importer.call(Repo, user, DemoData.fixtures()) == :exists

    assert rows(
             "SELECT id,import_id,track_id FROM points WHERE import_id IS NOT NULL ORDER BY id"
           ) == before

    assert rows("SELECT id FROM tracks ORDER BY id") == tracks

    assert rows("SELECT track_id FROM points WHERE id=ANY($1) ORDER BY id", [[live, foreign]]) ==
             [[nil], [nil]]

    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end
end
