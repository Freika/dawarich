defmodule DawarichWeb.A12f3aPProviderClosureTest do
  use Dawarich.IngestCase
  import Phoenix.ConnTest
  alias Dawarich.{Places.Nearby, TtlCache}

  defmodule FakeHttp do
    use Agent

    def start_link(_),
      do:
        Agent.start_link(fn -> %{response: {:ok, 200, "{}"}, requests: []} end, name: __MODULE__)

    def reset,
      do: Agent.update(__MODULE__, fn _ -> %{response: {:ok, 200, "{}"}, requests: []} end)

    def respond(outcome), do: Agent.update(__MODULE__, &%{&1 | response: outcome})
    def requests, do: Agent.get(__MODULE__, & &1.requests)

    def request(url, headers),
      do:
        Agent.get_and_update(
          __MODULE__,
          &{&1.response, %{&1 | requests: &1.requests ++ [{url, headers}]}}
        )
  end

  alias Dawarich.Test.{RailsUser, ParityHTML}
  @endpoint DawarichWeb.Endpoint

  setup do
    start_supervised!(FakeHttp)
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    old_http = Application.get_env(:dawarich, :geocoding_http)
    Application.put_env(:dawarich, :geocoding_http, FakeHttp)
    on_exit(fn -> Application.put_env(:dawarich, :geocoding_http, old_http) end)

    saved =
      Map.new(
        ~w(PHOTON_API_HOST GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY SELF_HOSTED DAWARICH_RAILS),
        &{&1, System.get_env(&1)}
      )

    for {key, _} <- saved, do: System.delete_env(key)
    System.put_env("DAWARICH_RAILS", "off")
    Repo.query!("DELETE FROM instance_settings")
    FakeHttp.reset()

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    :ok
  end

  defp fixture(id), do: File.read!("test/fixtures/places/a12f3a-#{id}.json") |> Jason.decode!()

  @tag a12f3a_p01: true
  test "P01: place list and drawer residuals matches current Rails contract without a native-owner Rails effect" do
    user = Dawarich.Test.FrameSeeds.user!(87001)
    foreign = Dawarich.Test.FrameSeeds.user!(87002)
    Dawarich.Test.FrameSeeds.place!(user.id, 870_101, "Own place")
    Dawarich.Test.FrameSeeds.place!(foreign.id, 870_102, "Foreign place")
    assert {:ok, %{name: "Own place"}} = Dawarich.PlaceDrawer.load(user, 870_101)
    assert Dawarich.PlaceDrawer.load(user, 870_102) == :rails

    for id <- [870_102, 870_103] do
      conn =
        RailsUser.signed_in(user.id)
        |> Plug.Conn.put_req_header("turbo-frame", "place-drawer")
        |> get("/places/#{id}")

      assert conn.status == 404
      refute conn.resp_body =~ "Foreign place"
    end

    assert commands() == []
  end

  @tag a12f3a_p04: true
  test "P04: place create adoption and tags matches current Rails contract without a native-owner Rails effect" do
    effects = fixture("p04")["effects"]

    entry = Enum.find(effects, &(&1["name"] == "update_omitted_tags_turbo_true"))
    user = Dawarich.Test.FrameSeeds.seed_place_remainder!(entry)

    for mode <- ["true", "false", nil] do
      if mode, do: System.put_env("SELF_HOSTED", mode), else: System.delete_env("SELF_HOSTED")
      session = RailsUser.session(user.id)
      id = hd(entry["before"]["places"])["id"]

      before =
        Repo.query!(
          "SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1",
          [id]
        ).rows

      attrs = %{
        "place" => %{"note" => "Keep tags"},
        "_method" => "patch",
        "authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session)
      }

      raw = Plug.Conn.Query.encode(attrs)

      conn =
        build_conn()
        |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
        |> Plug.Conn.put_req_header("accept", "text/vnd.turbo-stream.html")
        |> Plug.Conn.put_req_header("turbo-frame", "place-drawer")
        |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
        |> Plug.Conn.put_req_header("content-length", to_string(byte_size(raw)))
        |> dispatch(@endpoint, :post, "/places/#{id}", raw)

      assert conn.status == 200
      assert conn.resp_body =~ "Place updated successfully"

      assert Repo.query!(
               "SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1",
               [id]
             ).rows == before

      assert commands() == []
    end
  end

  @tag a12f3a_p02: true
  test "P02: nearby provider query and results matches current Rails contract without a native-owner Rails effect" do
    c = fixture("p02")

    user =
      Dawarich.Test.FrameSeeds.user!(87001, %{
        "timezone" => "Europe/Berlin",
        "onboarding_completed" => true
      })

    System.put_env("PHOTON_API_HOST", "photon.example.test")

    for mode <- ["true", "false", nil] do
      if mode, do: System.put_env("SELF_HOSTED", mode), else: System.delete_env("SELF_HOSTED")
      FakeHttp.reset()

      TtlCache.delete(
        {Dawarich.Geocoding.ResponseCache,
         "http://photon.example.test/reverse?distance_sort=true&lang=en&lat=51.3397&limit=3&lon=12.3731&radius=1.0"}
      )

      FakeHttp.respond(
        {:ok, 200, Jason.encode!(%{"type" => "FeatureCollection", "features" => [c["provider"]]})}
      )

      conn =
        RailsUser.signed_in(user.id) |> get("/places/nearby?" <> URI.encode_query(c["params"]))

      assert conn.status == c["status"]
      assert ParityHTML.normalize(conn.resp_body) == ParityHTML.normalize(c["html"])
      [{url, _}] = FakeHttp.requests()

      assert URI.decode_query(URI.parse(url).query) == %{
               "lang" => "en",
               "lat" => "51.3397",
               "lon" => "12.3731",
               "radius" => "1.0",
               "limit" => "3",
               "distance_sort" => "true"
             }

      assert commands() == []
    end

    assert Nearby.fetch(user, 0.0, 0.0, 0.5, 3) == []
    assert RailsUser.signed_in(user.id) |> get("/places/nearby") |> response(400) == ""
  end

  @tag a12f3a_p03: true
  test "P03: provider cache and error contracts matches current Rails contract without a native-owner Rails effect" do
    c = fixture("p02")

    config = %{
      enabled: true,
      source: :stored,
      provider: :photon,
      host: "photon.test.example.com",
      api_key: nil,
      use_https: false,
      rps: nil
    }

    cache_source = fixture("p03")
    key = Nearby.cache_key(config, 51.33971, 12.37311, 0.5, 3)
    assert key == cache_source["cache_key"]
    assert key == Nearby.cache_key(config, 51.33972, 12.37312, 0.5, 3)
    refute key == Nearby.cache_key(config, 51.33971, 12.37311, 1.0, 3)
    refute key == Nearby.cache_key(%{config | api_key: "synthetic"}, 51.33971, 12.37311, 0.5, 3)

    FakeHttp.respond(
      {:ok, 200, Jason.encode!(%{"type" => "FeatureCollection", "features" => [c["provider"]]})}
    )

    assert Nearby.fetch(nil, 51.33971, 12.37311, 0.5, 3, config: config, cache: true) ==
             c["results"]

    assert Nearby.fetch(nil, 51.33972, 12.37312, 0.5, 3, config: config, cache: true) ==
             c["results"]

    assert length(FakeHttp.requests()) == 1
    assert {:ok, _} = TtlCache.lookup({Nearby, key})
    [{{Nearby, ^key}, _, expires}] = :ets.lookup(TtlCache, {Nearby, key})
    assert (expires - System.monotonic_time(:millisecond)) in 3_590_000..3_600_000

    for {outcome, index} <-
          Enum.with_index([{:error, :timeout}, {:error, :tls}, {:ok, 429, ""}, {:ok, 503, ""}]) do
      FakeHttp.respond(outcome)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Nearby.fetch(nil, 51.34 + index, 12.37, 0.5, 3, config: config, cache: true) ==
                   []
        end)

      assert log =~ if(index == 2, do: "[error]", else: "[warning]")
      refute log =~ config.host
      refute log =~ "51.34"

      assert TtlCache.lookup({Nearby, Nearby.cache_key(config, 51.34 + index, 12.37, 0.5, 3)}) ==
               :error
    end

    assert commands() == []
  end
end

defmodule DawarichWeb.A12f3aPCLIClosureTest do
  use Dawarich.JobsCase
  alias Dawarich.{CLI, Jobs.Ownership, Places.JobCommands}

  defmodule FailingRepo do
    def query!(_, _, _), do: raise(DBConnection.ConnectionError, "synthetic database unavailable")
  end

  defmodule ReorderedBatchRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo

    def query!(sql, params, opts) do
      result = Dawarich.ScratchRepo.query!(sql, params, opts)

      if String.contains?(sql, "AND id<=$2"),
        do: %{result | rows: Enum.reverse(result.rows)},
        else: result
    end
  end

  defp ctx(repo \\ ScratchRepo) do
    {:ok, out} = StringIO.open("")
    {:ok, err} = StringIO.open("")
    %{repo: repo, out: out, err: err, stdin: out, env: %{}, now: ~U[2026-10-02 10:00:00.000000Z]}
  end

  defp text(pid), do: StringIO.contents(pid) |> elem(1)

  defp owner(type, runtime \\ :oban),
    do: Ownership.put!(ScratchRepo, "command:places." <> type, runtime)

  defp users(count) do
    rows(
      "INSERT INTO users(email,created_at,updated_at) SELECT 'closure-' || n || '@example.test',now(),now() FROM generate_series(1,$1) n RETURNING id",
      [count]
    )
    |> List.flatten()
    |> Enum.sort()
  end

  @tag a12f3a_p07: true
  test "P07: places cli name-backfill dispatch matches current Rails contract without a native-owner Rails effect" do
    owner("bulk_name_fetch")

    for argv <- [
          ["places", "backfill-names"],
          ["dawarich:backfill_place_names"],
          ["dawarich:backfill_place_names[]"]
        ] do
      context = ctx()
      assert CLI.run(argv, context) == 0
      source = File.read!("test/fixtures/places/a12f3a-p07.json") |> Jason.decode!()
      assert text(context.out) == source["stdout"]
      assert text(context.err) == source["stderr"]
    end

    assert rows("SELECT command_type,payload FROM job_outbox ORDER BY scheduled_at") ==
             List.duplicate(["places.bulk_name_fetch", %{}], 3)

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3a_p08: true
  test "P08: places cli cleanup scheduling matches current Rails contract without a native-owner Rails effect" do
    owner("orphan_cleanup")
    ids = users(102)
    rows("UPDATE users SET updated_at=now() WHERE id=ANY($1)", [Enum.take(ids, 20)])
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [List.last(ids)])

    for repo <- [ScratchRepo, ReorderedBatchRepo] do
      rows("DELETE FROM job_outbox")
      context = ctx(repo)
      assert CLI.run(["places", "cleanup-suggested"], context) == 0

      scheduled =
        rows("SELECT command_type,payload,scheduled_at FROM job_outbox ORDER BY scheduled_at")

      assert Enum.map(scheduled, &Enum.at(&1, 0)) ==
               List.duplicate("places.orphan_cleanup", 101)

      assert scheduled
             |> Enum.map(fn [_, %{"user_id" => id}, _] -> id end)
             |> Enum.chunk_every(100)
             |> Enum.map(&Enum.sort/1) == ids |> Enum.take(101) |> Enum.chunk_every(100)

      assert Enum.map(scheduled, &Enum.at(&1, 2)) ==
               Enum.map(0..100, &DateTime.add(context.now, &1 * 100_000, :microsecond))

      assert text(context.out) == ""
      assert text(context.err) == ""
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    end
  end

  @tag a12f3a_p09: true
  test "P09: places cli drain remedy and errors matches current Rails contract without a native-owner Rails effect" do
    [user] = users(1)

    rows(
      "INSERT INTO places(user_id,name,source,note,latitude,longitude,created_at,updated_at) VALUES($1,'Suggested place',1,NULL,0,0,now(),now()),($1,'Saved',0,NULL,0,0,now(),now()),($1,'Note',1,'keep',0,0,now(),now())",
      [user]
    )

    context = ctx()
    assert CLI.run(["places", "orphan-count"], context) == 0
    source = File.read!("test/fixtures/places/a12f3a-p09.json") |> Jason.decode!()
    assert text(context.out) == "#{source["unlinked_count"]}\n"
    assert text(context.err) == ""
    [[place]] = rows("SELECT id FROM places WHERE user_id=$1 AND name='Suggested place'", [user])

    rows(
      "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,status,deleted_at,created_at,updated_at) VALUES($1,$2,'Tombstone',now(),now()+interval '1 hour',60,2,now(),now(),now())",
      [user, place]
    )

    retained = ctx()
    assert CLI.run(["places", "orphan-count"], retained) == 0
    assert text(retained.out) == "#{source["retained_count"]}\n"
    failing = ctx(FailingRepo)
    assert CLI.run(["places", "orphan-count"], failing) == 1
    assert text(failing.out) == ""
    assert text(failing.err) =~ "synthetic database unavailable"
  end

  @tag a12f3a_p10: true
  test "P10: cli aliases and persisted-owner concurrency matches current Rails contract without a native-owner Rails effect" do
    [user] = users(1)
    owner("orphan_cleanup")
    at = ~U[2026-10-02 10:00:07.100000Z]
    assert JobCommands.orphan_cleanup(ScratchRepo, user, at) == :ok

    assert rows("SELECT command_type,payload,scheduled_at FROM job_outbox") == [
             ["places.orphan_cleanup", %{"user_id" => user}, at]
           ]

    for argv <- [
          ["places", "backfill-names", "extra"],
          ["places", "cleanup-suggested", "extra"],
          ["places", "orphan-count", "extra"],
          ["dawarich:backfill_place_names[1]"],
          ["dawarich:cleanup_suggested_places[1]"],
          ["dawarich:cleanup_suggested_places", "extra"]
        ] do
      assert CLI.run(argv, ctx()) == 1
    end

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
    owner("orphan_cleanup", :sidekiq)
    assert JobCommands.orphan_cleanup(ScratchRepo, user, at) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             [
               "places_orphan_cleanup",
               %{"user_id" => user, "scheduled_at" => DateTime.to_iso8601(at)}
             ]
           ]

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
  end
end
