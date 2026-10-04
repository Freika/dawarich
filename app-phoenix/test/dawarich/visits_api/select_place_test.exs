defmodule Dawarich.VisitsApi.SelectPlaceTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.VisitsApi.{Read, SelectPlace}

  @now ~U[2026-10-03 12:00:00.000000Z]
  @stamp ~N[2026-09-01 12:00:00.000000]
  @photon %{
    "name" => "Chosen",
    "latitude" => 52.52,
    "longitude" => 13.405,
    "osm_id" => 42,
    "geodata" => %{"properties" => %{"osm_id" => 42}}
  }

  setup do
    start_supervised!(Dawarich.Geocoding.FakeHttp)
    rows("TRUNCATE places,visits CASCADE")
    rows("DELETE FROM instance_settings")

    ScratchRepo.insert_all("users", [
      %{
        id: 953_001,
        email: "a4rest-select@example.invalid",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    for {id, name, lon} <- [
          {953_201, "Wrong name", 13.405},
          {953_202, "Chosen", 13.4051},
          {953_203, "Chosen", 13.406}
        ] do
      rows(
        "INSERT INTO places (id,user_id,name,latitude,longitude,lonlat,geodata,created_at,updated_at) VALUES ($1,953001,$2,52.52,$3::double precision,ST_SetSRID(ST_MakePoint($3::double precision,52.52),4326),$4,$5,$5)",
        [id, name, lon, %{"properties" => %{"osm_id" => 42}}, @stamp]
      )
    end

    for id <- [953_301, 953_302] do
      ScratchRepo.insert_all("visits", [
        %{
          id: id,
          user_id: 953_001,
          place_id: 953_201,
          name: "Before",
          status: 0,
          duration: 60,
          started_at: NaiveDateTime.add(@stamp, (id - 953_301) * 86400),
          ended_at: NaiveDateTime.add(@stamp, (id - 953_301) * 86400 + 3600),
          created_at: @stamp,
          updated_at: @stamp
        }
      ])
    end

    :ok
  end

  test "select_place dedups at 50m and locks chosen name" do
    assert {:ok, {:object, fields}} = select(953_301, @photon)
    payload = Map.new(fields)
    assert payload["id"] == 953_202
    assert payload["source"] == "manual"
    assert payload["visits_count"] == 1
    refute Map.has_key?(payload, "name_locked")

    assert rows("SELECT name_locked_at FROM places WHERE id=953202") == [
             [DateTime.to_naive(@now)]
           ]

    rows("UPDATE visits SET place_id=NULL WHERE id=953301")
    rows("DELETE FROM places WHERE id=953202")
    assert {:ok, {:object, fields}} = select(953_302, @photon)
    refute Map.new(fields)["id"] in [953_201, 953_203]

    assert {:error, 422, "param is missing or the value is empty or invalid: name"} =
             select(953_302, Map.delete(@photon, "name"))

    assert {:error, 422, "param is missing or the value is empty or invalid: latitude"} =
             select(953_302, Map.put(@photon, "latitude", 91))
  end

  test "select_place honors geodata setting and confirms visit" do
    ScratchRepo.insert_all("instance_settings", [
      %{key: "store_geodata", value: false, created_at: @stamp, updated_at: @stamp}
    ])

    attrs = Map.put(@photon, "name", "New place")
    assert {:ok, {:object, fields}} = select(953_301, attrs)
    id = Map.new(fields)["id"]

    assert rows("SELECT source,geodata,name_locked_at FROM places WHERE id=$1", [id]) == [
             [1, %{}, DateTime.to_naive(@now)]
           ]

    assert rows("SELECT status,name,place_id FROM visits WHERE id=953301") == [
             [1, "New place", id]
           ]

    assert Read.possible_places(953_001, 959_999, "UTC") == :not_found
  end

  test "possible_places prepends current and hands enabled provider path back" do
    assert {:ok, [{:object, fields}]} = Read.possible_places(953_001, 953_301, "UTC")
    assert Map.new(fields)["id"] == 953_201
    assert Map.new(fields)["osm_id"] == 42

    ScratchRepo.insert_all("instance_settings", [
      %{
        key: "photon_api_host",
        value: "synthetic.invalid",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    assert {:replay, _} = Read.possible_places(953_001, 953_301, "UTC")
    assert Dawarich.Geocoding.FakeHttp.requests() == []
    rows("UPDATE visits SET place_id=NULL WHERE id=953301")
    assert {:ok, []} = Read.possible_places(953_001, 953_301, "UTC")
    assert rows("SELECT COUNT(*) FROM phoenix.rails_commands") == [[0]]
  end

  test "select_place transaction lock serializes dedup and releases on rollback" do
    attrs = Map.put(@photon, "name", "Concurrent")
    assert serialized(attrs, :commit) == :ok
    assert rows("SELECT COUNT(*) FROM places WHERE name='Concurrent'") == [[1]]
    assert serialized(Map.merge(attrs, %{"name" => "Rollback", "osm_id" => 43}), :rollback) == :ok
    assert rows("SELECT COUNT(*) FROM places WHERE name='Rollback'") == [[1]]

    assert rows(
             "SELECT COUNT(*) FROM pg_locks WHERE locktype='advisory' AND pid IN (SELECT pid FROM pg_stat_activity WHERE datname=current_database())"
           ) == [[0]]
  end

  defp serialized(attrs, outcome) do
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          [[pid]] = rows("SELECT pg_backend_pid()")
          assert {:ok, _} = select(953_301, attrs)
          send(parent, {:holding, pid})

          receive do
            :release ->
              if outcome == :rollback, do: ScratchRepo.rollback(:rolled_back), else: :committed
          end
        end)
      end)

    assert_receive {:holding, holding}

    waiter =
      Task.async(fn ->
        ScratchRepo.checkout(fn ->
          [[pid]] = rows("SELECT pg_backend_pid()")
          send(parent, {:waiting, pid})
          select(953_302, attrs)
        end)
      end)

    assert_receive {:waiting, waiting}

    try do
      assert blocked?(waiting, holding, System.monotonic_time(:millisecond) + 1000)
    after
      send(holder.pid, :release)
    end

    assert Task.await(holder) in [{:ok, :committed}, {:error, :rolled_back}]
    assert {:ok, _} = Task.await(waiter)
    :ok
  end

  defp blocked?(waiting, holding, deadline) do
    cond do
      rows("SELECT $2::int=ANY(pg_blocking_pids($1::int))", [waiting, holding]) == [[true]] ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        blocked?(waiting, holding, deadline)
    end
  end

  defp select(id, attrs), do: SelectPlace.call(953_001, id, attrs, "UTC", @now)
end
