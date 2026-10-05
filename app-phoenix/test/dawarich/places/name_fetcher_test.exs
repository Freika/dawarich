defmodule Dawarich.Places.NameFetcherTest do
  use Dawarich.GeocodingCase, async: false
  alias Dawarich.Geocoding.{Config, Query}
  alias Dawarich.Places.{NameBuilder, NameFetcher, NameFetchWorker}

  setup do
    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('names@example.test',now(),now()) RETURNING id"
      )

    on_exit(fn ->
      rows("DELETE FROM visits WHERE user_id=$1", [user])
      rows("DELETE FROM places WHERE user_id=$1", [user])
    end)

    config =
      Config.resolve(ScratchRepo, %{
        "PHOTON_API_HOST" => "names.example.test",
        "STORE_GEODATA" => "true"
      })

    {url, _, _} = Query.build(config, {0.0, 0.0}, [limit: 1, distance_sort: true], "test")
    %{user: user, config: config, url: url}
  end

  test "limit-one naming preserves locked fields and renames only source stale visits", %{
    user: user,
    config: config,
    url: url
  } do
    assert NameBuilder.build(%{
             "name" => " yes ",
             "street" => " Road ",
             "housenumber" => 7,
             "city" => "Road",
             "state" => " NO "
           }) == "Road, 7"

    assert NameBuilder.build(%{"name" => "no"}) == nil
    place = place(user, "Old name")
    default = visit(user, place, "Suggested place")
    stale = visit(user, place, "Old name")
    custom = visit(user, place, "Custom visit")

    data = %{
      "properties" => %{
        "name" => " Station ",
        "street" => " Road ",
        "housenumber" => "7",
        "city" => "Berlin",
        "country" => "Germany",
        "state" => "Berlin"
      }
    }

    FakeHttp.stub(url, 200, Jason.encode!(%{"type" => "FeatureCollection", "features" => [data]}))
    assert NameFetcher.run(ScratchRepo, user, place, config) == :ok

    assert rows(
             "SELECT name,city,country,geodata,source,name_locked_at,reverse_geocoded_at FROM places WHERE id=$1",
             [place]
           ) == [["Station, Road, 7, Berlin", "Berlin", "Germany", data, 2, nil, nil]]

    assert rows("SELECT name FROM visits WHERE id=ANY($1) ORDER BY id", [[default, stale, custom]]) ==
             [["Station, Road, 7, Berlin"], ["Station, Road, 7, Berlin"], ["Custom visit"]]

    assert FakeHttp.requests() == [url]
    assert URI.decode_query(URI.parse(url).query)["limit"] == "1"
    refute Map.has_key?(URI.decode_query(URI.parse(url).query), "radius")

    rows(
      "UPDATE places SET name='Locked',name_locked_at=timestamp '2026-10-04',city='Retained city',country='Retained country' WHERE id=$1",
      [place]
    )

    locked_default = visit(user, place, "Suggested place")
    locked_data = %{"properties" => %{"name" => "Replacement", "city" => " ", "country" => ""}}
    clear_cache(url)

    FakeHttp.stub(
      url,
      200,
      Jason.encode!(%{"type" => "FeatureCollection", "features" => [locked_data]})
    )

    assert NameFetcher.run(ScratchRepo, user, place, %{config | store_geodata: false}) == :ok

    assert rows(
             "SELECT name,city,country,geodata,source,name_locked_at FROM places WHERE id=$1",
             [place]
           ) == [
             [
               "Locked",
               "Retained city",
               "Retained country",
               data,
               2,
               ~N[2026-10-04 00:00:00.000000]
             ]
           ]

    assert rows("SELECT name FROM visits WHERE id=$1", [locked_default]) == [["Locked"]]
    before = rows("SELECT row_to_json(p) FROM places p WHERE id=$1", [place])
    assert NameFetcher.run(ScratchRepo, user, place, %{enabled: false}) == :ok
    assert NameFetcher.run(ScratchRepo, user + 1, place, config) == :missing
    assert NameFetcher.run(ScratchRepo, user, -1, config) == :missing

    for features <- [[], [%{}]] do
      clear_cache(url)

      FakeHttp.stub(
        url,
        200,
        Jason.encode!(%{"type" => "FeatureCollection", "features" => features})
      )

      assert NameFetcher.run(ScratchRepo, user, place, config) == :ok
      assert rows("SELECT row_to_json(p) FROM places p WHERE id=$1", [place]) == before
    end

    clear_cache(url)
    empty = %{"properties" => %{}}

    FakeHttp.stub(
      url,
      200,
      Jason.encode!(%{"type" => "FeatureCollection", "features" => [empty]})
    )

    assert NameFetcher.run(ScratchRepo, user, place, config) == :ok
    assert rows("SELECT name,geodata FROM places WHERE id=$1", [place]) == [["Locked", empty]]
  end

  test "provider failures retain source no-change and safe error outcome", %{
    user: user,
    config: config,
    url: url
  } do
    place = place(user, "Suggested place")
    before = rows("SELECT row_to_json(p) FROM places p WHERE id=$1", [place])

    for failure <- [:timeout, :tls, :raise, :parse, :limited] do
      clear_cache(url)

      case failure do
        :raise -> FakeHttp.stub_raise(url)
        :parse -> FakeHttp.stub(url, 200, "not json")
        :limited -> FakeHttp.stub(url, 429, "slow")
        reason -> FakeHttp.stub_error(url, reason)
      end

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert NameFetcher.run(ScratchRepo, user, place, config) == :ok
        end)

      assert log =~ "geocoding.name_lookup_failed"
      refute log =~ "names.example.test"
      assert rows("SELECT row_to_json(p) FROM places p WHERE id=$1", [place]) == before
    end

    clear_cache(url)

    FakeHttp.stub(
      url,
      200,
      Jason.encode!(%{
        "type" => "FeatureCollection",
        "features" => [%{"properties" => %{"name" => String.duplicate("x", 256)}}]
      })
    )

    args = %{"user_id" => user, "place_id" => place, "event_id" => Ecto.UUID.generate()}

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert NameFetchWorker.run(ScratchRepo, args, config: config) == :ok
      end)

    assert log =~ "geocoding.name_write_failed"
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, args["event_id"])
    assert rows("SELECT row_to_json(p) FROM places p WHERE id=$1", [place]) == before
    clear_cache(url)

    FakeHttp.stub(
      url,
      200,
      Jason.encode!(%{
        "type" => "FeatureCollection",
        "features" => [%{"properties" => %{"name" => "New"}}]
      })
    )

    assert NameFetchWorker.run(ScratchRepo, args, config: config) == :ok
    assert rows("SELECT row_to_json(p) FROM places p WHERE id=$1", [place]) == before
    assert NameFetchWorker.__opts__()[:max_attempts] == 26
  end

  test "missing or foreign source place retries without claiming the naming unit", %{
    user: user,
    config: config
  } do
    place = place(user, "Retained place")
    before = rows("SELECT row_to_json(p) FROM places p WHERE id=$1", [place])

    for {owner, id} <- [{user, -1}, {user + 1, place}] do
      event = Ecto.UUID.generate()
      args = %{"user_id" => owner, "place_id" => id, "event_id" => event}
      assert NameFetchWorker.run(ScratchRepo, args, config: config) == {:error, :not_found}
      refute Dawarich.Jobs.Processed.done?(ScratchRepo, event)
      assert rows("SELECT row_to_json(p) FROM places p WHERE id=$1", [place]) == before
    end

    assert FakeHttp.requests() == []
  end

  defp place(user, name) do
    [[id]] =
      rows(
        "INSERT INTO places(user_id,name,source,latitude,longitude,created_at,updated_at) VALUES($1,$2,2,0,0,now(),now()) RETURNING id",
        [user, name]
      )

    id
  end

  defp visit(user, place, name) do
    [[id]] =
      rows(
        "INSERT INTO visits(user_id,place_id,name,status,duration,started_at,ended_at,created_at,updated_at) VALUES($1,$2,$3,0,60,timestamp '2026-10-04'+(SELECT count(*) FROM visits WHERE place_id=$2)*interval '1 minute',timestamp '2026-10-05',now(),now()) RETURNING id",
        [user, place, name]
      )

    id
  end

  defp clear_cache(url), do: Dawarich.Redis.cache_command(["DEL", url])
end
