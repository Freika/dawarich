defmodule Dawarich.VisitsApi.ReadTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.VisitsApi.Read

  setup do
    owner = user!()
    other = user!()
    now = ~N[2026-09-01 12:00:00]

    Repo.query!(
      "INSERT INTO places (id,user_id,name,latitude,longitude,lonlat,created_at,updated_at) VALUES (953131,$1,'Inside',52.52,13.405,ST_SetSRID(ST_MakePoint(13.405,52.52),4326),$2,$2)",
      [owner, now]
    )

    Repo.insert_all("areas", [
      %{
        id: 953_121,
        user_id: owner,
        name: "Area",
        latitude: 52.6,
        longitude: 13.6,
        radius: 100,
        created_at: now,
        updated_at: now
      }
    ])

    visits = [
      %{id: 953_301, place_id: 953_131, confidence: 70},
      %{id: 953_302, area_id: 953_121, confidence: 40},
      %{id: 953_303, confidence: 39},
      %{id: 953_304, confidence: nil},
      %{id: 953_305, deleted_at: now},
      %{id: 953_306, status: 2},
      %{id: 953_307, user_id: other}
    ]

    for {attrs, index} <- Enum.with_index(visits) do
      row =
        Map.merge(
          %{
            user_id: owner,
            name: "Synthetic visit",
            status: 1,
            duration: 180,
            started_at: NaiveDateTime.add(now, index * 60),
            ended_at: NaiveDateTime.add(now, 10800),
            created_at: now,
            updated_at: now
          },
          attrs
        )

      Repo.insert_all("visits", [row])
    end

    %{owner: owner}
  end

  test "time finder includes visits crossing end_at and excludes tombstones", %{owner: owner} do
    assert {:ok, rows, []} = Read.index(owner, range(), "UTC")
    assert ids(rows) == [953_301, 953_302, 953_303, 953_304]
    assert Read.show(owner, 953_305, "UTC") == :not_found
    assert Read.show(owner, 953_307, "UTC") == :not_found
    assert Read.index(owner, %{}, "UTC") == {:error, 400, "Invalid date format"}

    assert Read.index(owner, %{"start_at" => "bad", "end_at" => "bad"}, "UTC") ==
             {:error, 400, "Invalid date format"}

    assert Read.index(owner, %{"start_at" => "nonsense", "end_at" => "nonsense"}, "UTC") ==
             {:error, 400, "Invalid date format"}

    assert {:replay, _} = Read.index(owner, %{"start_at" => "pst", "end_at" => "pst"}, "UTC")

    assert {:replay, _} =
             Read.index(owner, %{"start_at" => "September", "end_at" => "September"}, "UTC")
  end

  test "bbox combines area and place and reverses time ordering", %{owner: owner} do
    box = %{
      "selection" => "true",
      "sw_lat" => "52",
      "sw_lng" => "13",
      "ne_lat" => "53",
      "ne_lng" => "14"
    }

    assert {:ok, rows, []} = Read.index(owner, box, "UTC")
    assert ids(rows) == [953_302, 953_301]
    assert {:ok, rows, []} = Read.index(owner, Map.merge(box, range()), "UTC")
    assert ids(rows) == [953_302, 953_301]

    assert {:ok, [], []} =
             Read.index(owner, %{box | "sw_lat" => "52.6", "sw_lng" => "13.6"}, "UTC")
  end

  test "page absent returns all and page present emits exact count headers", %{owner: owner} do
    now = ~N[2026-09-01 12:10:00]

    for index <- 1..101,
        do:
          Repo.insert_all("visits", [
            %{
              id: 954_000 + index,
              user_id: owner,
              name: "Synthetic page",
              status: 1,
              duration: 10,
              started_at: NaiveDateTime.add(now, index),
              ended_at: NaiveDateTime.add(now, 600),
              created_at: now,
              updated_at: now
            }
          ])

    assert {:ok, rows, []} = Read.index(owner, range(), "UTC")
    assert length(rows) == 105

    assert {:ok, rows, headers} =
             Read.index(owner, Map.merge(range(), %{"page" => "2", "per_page" => "2"}), "UTC")

    assert ids(rows) == [953_303, 953_304]
    assert headers == [{"x-current-page", "2"}, {"x-total-pages", "53"}, {"x-total-count", "105"}]

    assert {:ok, rows, headers} =
             Read.index(owner, Map.merge(range(), %{"page" => "1", "per_page" => "999"}), "UTC")

    assert length(rows) == 105
    assert List.keyfind(headers, "x-total-pages", 0) == {"x-total-pages", "1"}
  end

  test "confidence boundaries and place fallback match serializer", %{owner: owner} do
    assert {:ok, rows, []} = Read.index(owner, range(), "Europe/Berlin")
    maps = Enum.map(rows, fn {:object, fields} -> Map.new(fields) end)
    assert Enum.map(maps, & &1["confidence_band"]) == ["high", "medium", "low", nil]
    assert hd(maps)["started_at"] == "2026-09-01T14:00:00.000+02:00"

    assert maps |> Enum.at(1) |> Map.fetch!("place") ==
             {:object, [{"latitude", 52.6}, {"longitude", 13.6}, {"id", nil}]}

    assert maps |> Enum.at(3) |> Map.fetch!("place") ==
             {:object, [{"latitude", nil}, {"longitude", nil}, {"id", nil}]}

    assert commands() == []

    Repo.query!("UPDATE places SET lonlat=NULL WHERE id=953131")
    assert {:ok, {:object, fields}} = Read.show(owner, 953_301, "UTC")

    assert Map.new(fields)["place"] ==
             {:object, [{"latitude", 52.52}, {"longitude", 13.405}, {"id", 953_131}]}
  end

  defp range, do: %{"start_at" => "2026-09-01T12:00:00Z", "end_at" => "2026-09-01T13:00:00Z"}
  defp ids(rows), do: Enum.map(rows, fn {:object, fields} -> Map.new(fields)["id"] end)
end
