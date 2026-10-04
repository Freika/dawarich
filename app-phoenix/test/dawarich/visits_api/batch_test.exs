defmodule Dawarich.VisitsApi.BatchTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.VisitsApi.Batch

  @now ~U[2026-10-03 12:00:00.000000Z]
  @stamp ~N[2026-09-01 12:00:00.000000]
  @entry %{
    "name" => "Nearby",
    "latitude" => 52.52,
    "longitude" => 13.405,
    "started_at" => "2026-09-01T12:00:00Z",
    "ended_at" => "2026-09-01T13:00:00Z"
  }

  setup do
    rows("TRUNCATE places,visits CASCADE")
    rows("DELETE FROM instance_settings")

    ScratchRepo.insert_all("users", [
      %{
        id: 953_001,
        email: "a4rest-batch@example.invalid",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    rows(
      "INSERT INTO places (id,user_id,name,latitude,longitude,lonlat,created_at,updated_at) VALUES (953201,953001,'Nearby',52.52,13.405,ST_SetSRID(ST_MakePoint(13.405,52.52),4326),$1,$1)",
      [@stamp]
    )

    ScratchRepo.insert_all("visits", [
      %{
        id: 953_301,
        user_id: 953_001,
        place_id: 953_201,
        name: "Nearby",
        status: 0,
        duration: 60,
        started_at: @stamp,
        ended_at: ~N[2026-09-01 13:00:00],
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    :ok
  end

  test "batch allows 100 rejects 101 and commits valid siblings" do
    assert {:ok, result} = batch(List.duplicate(Map.put(@entry, "status", "suggested"), 100))
    assert result.duplicate_count == 100
    assert result.created_count == 0
    assert result.failed_count == 0

    assert {:error, 422, _, %{"limit" => 100, "requested" => 101}} =
             batch(List.duplicate(@entry, 101))

    new =
      Map.merge(@entry, %{
        "started_at" => "2026-09-02T12:00:00Z",
        "ended_at" => "2026-09-02T13:00:00Z"
      })

    assert {:ok, result} = batch([new, %{}, "bad"])
    assert result.created_count == 1
    assert result.failed_count == 2
    assert Enum.map(result.results, & &1.status) == ["created", "failed", "failed"]
    assert rows("SELECT COUNT(*) FROM visits") == [[2]]
    assert rows("SELECT COUNT(*) FROM phoenix.rails_commands") == [[1]]
    assert {:error, 422, _} = batch([])
  end

  test "batch duplicate tombstone omits visit and reports exact counters" do
    rows("UPDATE visits SET deleted_at=$1 WHERE id=953301", [@stamp])
    assert {:ok, result} = batch([Map.put(@entry, "status", "suggested")])
    assert result.created_count == 0
    assert result.duplicate_count == 1
    assert result.failed_count == 0
    assert result.results == [%{index: 0, status: "duplicate"}]
    assert rows("SELECT COUNT(*) FROM phoenix.rails_commands") == [[0]]
  end

  defp batch(entries), do: Batch.call(953_001, entries, "UTC", @now)
end
