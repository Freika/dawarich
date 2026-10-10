defmodule Dawarich.Achievements.CollectionTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.Collection
  @root Path.expand("../../fixtures/achievements_ui", __DIR__)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(countries regions))

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(901,'collection@example.test',now(),now())"
    )

    rows(
      "INSERT INTO countries(iso_a2,iso_a3,name,geom,created_at,updated_at) VALUES('DE','DEU','Germany',ST_GeomFromText('MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))',4326),now(),now()),('FR','FRA','France',ST_GeomFromText('MULTIPOLYGON (((12.5 51.25,12.5 51.375,12.625 51.375,12.625 51.25,12.5 51.25)))',4326),now(),now())"
    )

    rows(
      "INSERT INTO regions(code,geom,created_at,updated_at) VALUES('DE-BY',ST_GeomFromText('MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))',4326),now(),now())"
    )

    :ok
  end

  for path <- Path.wildcard(Path.join(@root, "*-*.json")) do
    @fixture path |> File.read!() |> Jason.decode!()

    test "actual Rails #{@fixture["name"]}" do
      fixture = @fixture
      expected = fixture["view"]
      uri = URI.parse(fixture["path"])

      if fixture["seed_state"] do
        rows(
          "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(901,'exploration',$1,now(),now())",
          [fixture["seed_state"]]
        )
      end

      params =
        case uri.path do
          "/achievements/" <> key -> Map.put(URI.decode_query(uri.query || ""), "key", key)
          "/achievements" -> URI.decode_query(uri.query || "")
        end

      assert {:ok, view} =
               Collection.load(ScratchRepo, 901, params, %{
                 locale: fixture["settings"]["locale"],
                 settings: fixture["settings"],
                 now: ~U[2026-07-19 10:00:00Z]
               })

      actual = view |> Jason.encode!() |> Jason.decode!()
      assert Map.take(actual, Map.keys(expected)) == expected
      assert length(Map.get(view, :children, [])) <= 12

      if is_nil(fixture["seed_state"]),
        do: assert([[0]] == rows("SELECT count(*) FROM achievement_progresses"))

      assert rows("SELECT state FROM achievement_progresses WHERE user_id=901") ==
               if(fixture["state"], do: [[fixture["state"]]], else: [])
    end
  end

  test "a user without a time-zone setting gets TIME_ZONE's dates near midnight" do
    saved = System.get_env("TIME_ZONE")
    System.put_env("TIME_ZONE", "Europe/Berlin")

    on_exit(fn ->
      if saved, do: System.put_env("TIME_ZONE", saved), else: System.delete_env("TIME_ZONE")
    end)

    prior = Application.fetch_env(:dawarich, :achievement_ui_now)
    Application.put_env(:dawarich, :achievement_ui_now, fn -> ~U[2026-07-19 23:45:00Z] end)

    on_exit(fn ->
      case prior do
        {:ok, clock} -> Application.put_env(:dawarich, :achievement_ui_now, clock)
        :error -> Application.delete_env(:dawarich, :achievement_ui_now)
      end
    end)

    earned =
      Map.new(
        Dawarich.Achievements.Registry.find("country_de").region_codes,
        &{&1, "2026-07-19T23:30:00Z"}
      )

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(901,'exploration',$1,now(),now())",
      [%{"earned" => earned}]
    )

    context = DawarichWeb.AchievementContext.for_user(%{settings: %{"locale" => "en"}}, "en")

    assert {:ok, view} = Collection.load(ScratchRepo, 901, %{"key" => "country_de"}, context)
    assert view.completed_on == ~D[2026-07-20]
    assert view.set["card"]["earned_label"] == "Unlocked · 20 Jul 2026"
    assert hd(view.children)["earned_label"] == "Unlocked · 20 Jul 2026"

    assert [["2026-07-20T01:45:00+02:00"]] ==
             rows(
               "SELECT state->'celebrated'->>'country_de' FROM achievement_progresses WHERE user_id=901"
             )
  end

  test "a render converts every unlock date with one cold catalogue query and no warm queries" do
    earned =
      Dawarich.Achievements.Registry.find("country_de").region_codes
      |> Map.new(&{&1, "2026-07-19T10:00:00Z"})
      |> Map.put("AQ", "2026-07-18T10:00:00Z")

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(901,'exploration',$1,now(),now())",
      [%{"earned" => earned, "celebrated" => %{"country_de" => "x", "country_aq" => "x"}}]
    )

    context = %{locale: "en", settings: %{"timezone" => "Europe/Berlin"}, now: DateTime.utc_now()}
    test_pid = self()
    id = "achievement-zone-queries-#{inspect(test_pid)}"

    :telemetry.attach(
      id,
      [:dawarich, :repo, :query],
      fn _event, _measurements, meta, _ ->
        if meta.query =~ "pg_timezone_names", do: send(test_pid, :zone_query)
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    for params <- [%{}, %{"key" => "country_de"}] do
      Dawarich.TimeZoneNames.invalidate(Dawarich.Repo)
      assert {:ok, view} = Collection.load(ScratchRepo, 901, params, context)
      assert zone_queries() == 1, inspect(params)
      assert {:ok, ^view} = Collection.load(ScratchRepo, 901, params, context)
      assert zone_queries() == 0, inspect(params)
    end
  end

  defp zone_queries do
    receive do
      :zone_query -> 1 + zone_queries()
    after
      0 -> 0
    end
  end

  test "unknown hidden tier and flat/orphan routes match Rails" do
    context = %{locale: "en", settings: %{"timezone" => "UTC"}, now: DateTime.utc_now()}

    assert {:error, :not_found} =
             Collection.load(ScratchRepo, 901, %{"key" => "explorer_atlantis"}, context)

    assert {:redirect, "/achievements"} =
             Collection.load(ScratchRepo, 901, %{"key" => "border_hopper"}, context)

    assert {:redirect, "/achievements/continent_europe"} =
             Collection.load(ScratchRepo, 901, %{"key" => "country_fr"}, context)

    assert {:error, :not_found} =
             Collection.load(ScratchRepo, 901, %{"key" => "country_aq"}, context)
  end
end
