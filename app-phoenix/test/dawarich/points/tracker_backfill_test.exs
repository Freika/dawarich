defmodule Dawarich.Points.TrackerBackfillTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Points.TrackerBackfill

  test "matches tracker fallback precedence scopes and idempotent counts" do
    source = Fixtures.case!("tracker_records")
    Fixtures.load!(ScratchRepo, source)

    foreign =
      hd(source["input"]["users"])
      |> Map.merge(%{"id" => 170_102, "email" => "foreign@example.invalid"})

    Fixtures.row!(ScratchRepo, "users", foreign)
    point = hd(source["input"]["points"]) |> Map.merge(%{"id" => 190_001, "user_id" => 170_102})
    Fixtures.row!(ScratchRepo, "points", point)

    rows(
      "UPDATE points SET tracker_id='google-maps-timeline-export',raw_data=$1 WHERE id=170204",
      [%{"deviceTag" => " ", "tid" => " \t "}]
    )

    rows("UPDATE points SET tracker_id=NULL,raw_data=NULL WHERE id=170206")

    rows("""
    INSERT INTO points(id,user_id,timestamp,raw_data,created_at,updated_at)
    SELECT 200000+g*2,170101,100000+g,'{"deviceTag":" 9 ","tid":" first "}',
      '2026-10-03 12:00:00','2026-10-03 12:00:00' FROM generate_series(1,5001) g
    """)

    rows("""
    INSERT INTO points(id,user_id,timestamp,raw_data,created_at,updated_at)
    VALUES(200001,170101,1,'{"deviceTag":" ","tid":""}','2026-10-03 12:00:00','2026-10-03 12:00:00')
    """)

    untouched =
      rows(
        "SELECT id,tracker_id,updated_at FROM points WHERE id IN (170203,170205,170208,190001,200001) ORDER BY id"
      )

    parent = self()

    assert TrackerBackfill.run(ScratchRepo, 170_101,
             after_batch: fn n, cursor -> send(parent, {:batch, n, cursor}) end
           ) == 5006

    assert_receive {:batch, 5000, first}
    assert_receive {:batch, 6, 210_002}
    assert first < 210_002
    assert rows("SELECT tracker_id FROM points WHERE id=170202") == [["google-records-device-7"]]
    assert rows("SELECT tracker_id FROM points WHERE id=170204") == [["\t"]]
    assert rows("SELECT tracker_id FROM points WHERE id=170206") == [["legacy-import-170801"]]

    assert rows(
             "SELECT count(*) FROM points WHERE id>=200002 AND tracker_id='google-records-device-9'"
           ) == [[5001]]

    assert rows(
             "SELECT count(*) FROM points WHERE id>=200002 AND updated_at>'2026-10-03 12:00:00'"
           ) == [[5001]]

    assert rows(
             "SELECT id,tracker_id,updated_at FROM points WHERE id IN (170203,170205,170208,190001,200001) ORDER BY id"
           ) == untouched

    assert TrackerBackfill.run(ScratchRepo, 170_101) == 0
    assert TrackerBackfill.run(ScratchRepo, -1) == 0
  end
end
