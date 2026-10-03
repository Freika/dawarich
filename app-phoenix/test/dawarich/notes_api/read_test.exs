defmodule Dawarich.NotesApi.ReadTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.NotesApi.Read

  setup do
    owner = user!(%{settings: %{"timezone" => "UTC"}})
    other = user!()
    stamp = ~N[2026-09-01 12:00:00.123456]

    rows = [
      %{
        id: 952_201,
        user_id: owner,
        title: "Synthetic note",
        body: "Original body",
        noted_at: ~N[2026-09-01 22:30:00]
      },
      %{
        id: 952_202,
        user_id: owner,
        title: nil,
        body: "Standalone",
        noted_at: ~N[2026-09-02 12:00:00]
      },
      %{
        id: 952_203,
        user_id: owner,
        title: nil,
        body: "Trip",
        noted_at: ~N[2026-09-01 12:00:00],
        attachable_type: "Trip",
        attachable_id: 952_101
      },
      %{
        id: 952_204,
        user_id: owner,
        title: nil,
        body: "Place",
        noted_at: ~N[2026-09-01 12:01:00],
        attachable_type: "Place",
        attachable_id: 952_131
      },
      %{
        id: 952_205,
        user_id: other,
        title: nil,
        body: "Foreign",
        noted_at: ~N[2026-09-03 12:00:00]
      }
    ]

    for row <- rows,
        do: Repo.insert_all("notes", [Map.merge(%{created_at: stamp, updated_at: stamp}, row)])

    Repo.query!(
      "UPDATE notes SET lonlat = ST_SetSRID(ST_MakePoint(13.405,52.52),4326) WHERE id = 952201"
    )

    %{owner: owner, other: other}
  end

  test "notes filters compose and standalone is literal true", %{owner: owner} do
    assert {:ok, all} = Read.index(owner, %{}, "UTC")
    assert ids(all) == [952_202, 952_201, 952_204, 952_203]

    assert {:ok, attached} =
             Read.index(owner, %{"attachable_type" => "Trip", "attachable_id" => "952131"}, "UTC")

    assert attached == []
    assert {:ok, place} = Read.index(owner, %{"attachable_id" => "952131"}, "UTC")
    assert ids(place) == [952_204]
    assert {:ok, standalone} = Read.index(owner, %{"standalone" => "true"}, "UTC")
    assert ids(standalone) == [952_202, 952_201]

    for flag <- [true, "false", "1"],
        do: assert(Read.index(owner, %{"standalone" => flag}, "UTC") == {:ok, all})

    assert {:ok, []} =
             Read.index(owner, %{"standalone" => "true", "attachable_type" => "Trip"}, "UTC")
  end

  test "note date is UTC while timestamps serialize in request zone", %{owner: owner} do
    assert {:ok, {:object, fields}} = Read.show(owner, 952_201, "Europe/Berlin")
    assert Map.new(fields)["date"] == "2026-09-01"
    assert Map.new(fields)["noted_at"] == "2026-09-02T00:30:00.000+02:00"
    assert Map.new(fields)["created_at"] == "2026-09-01T14:00:00.123+02:00"
    assert Map.new(fields)["updated_at"] == "2026-09-01T14:00:00.123+02:00"

    assert Enum.map(fields, &elem(&1, 0)) ==
             ~w(id title body latitude longitude attachable_type attachable_id date noted_at created_at updated_at)
  end

  test "notes show is owner scoped with exact nullable geometry", %{owner: owner, other: other} do
    assert Read.show(other, 952_201, "UTC") == :not_found
    assert Read.show(owner, 959_999, "UTC") == :not_found
    assert {:ok, {:object, fields}} = Read.show(owner, 952_202, "UTC")
    assert Map.new(fields)["latitude"] == nil
    assert Map.new(fields)["longitude"] == nil
    assert Map.new(fields)["title"] == nil
    assert {:ok, {:object, coordinates}} = Read.show(owner, 952_201, "UTC")
    assert Map.new(coordinates)["latitude"] == 52.52
    assert Map.new(coordinates)["longitude"] == 13.405
    assert commands() == []
  end

  defp ids(terms), do: Enum.map(terms, fn {:object, fields} -> Map.new(fields)["id"] end)
end
