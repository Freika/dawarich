defmodule Dawarich.Insights.DetailsDBTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Redis, Repo}
  alias Dawarich.Insights.{Details, Fragments}
  import Dawarich.Test.InsightsSeeds

  @now ~U[2026-06-15 10:00:00Z]
  @digest_updated ~N[2024-03-05 00:00:00]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    start_cache!()
    %{user: user!()}
  end

  defp load(user, params), do: Details.load(user, params, now: @now, self_hosted: false)

  defp digests, do: Repo.query!("SELECT id, updated_at FROM digests ORDER BY id", []).rows

  test "Lite restricted and locked details return before yearly patterns", %{user: user} do
    yearly_digest!()

    cache!(
      Details.yearly_key(93, 2024, @digest_updated),
      <<0, 17, 1, -1.0::little-float-64, -1::little-signed-32, 4, 8, ?i, 86>>
    )

    Repo.query!("UPDATE users SET plan=0 WHERE id=93", [])
    id = "a12d1b4-restricted-queries"

    :telemetry.attach(
      id,
      [:dawarich, :repo, :query],
      fn _, _, meta, pid ->
        if String.contains?(meta.query, "digests"),
          do: send(pid, {:restricted_digest_query, meta.query})
      end,
      self()
    )

    try do
      for year <- ~w(2024 2025) do
        page = load(%{user | plan: 0}, %{"year" => year})
        assert page.restricted
        assert page.year_locked == (year == "2024")
        refute page.rails
        refute Map.has_key?(page, :yearly)
        refute Map.has_key?(page, :totals)
      end

      refute_receive {:restricted_digest_query, _}
    after
      :telemetry.detach(id)
    end
  end

  test "direct yearly reads preserve the explicitly scoped source stat list and cache precedence" do
    alias Dawarich.Insights.Details.Digests, as: DetailDigests

    oracle =
      Path.expand("../fixtures/a12d1b4/cache.json", __DIR__) |> File.read!() |> Jason.decode!()

    user!(180_101)
    Repo.query!("UPDATE stats SET year=2025, month=month+8 WHERE user_id=180101", [])

    Repo.query!("UPDATE stats SET updated_at=$1 WHERE user_id=180101 AND month=12", [
      ~N[2026-10-04 12:00:00]
    ])

    result = Repo.query!("SELECT * FROM stats WHERE user_id=180101 AND month=11", [])
    scoped = Enum.map(result.rows, &Map.new(Enum.zip(result.columns, &1)))
    assert Enum.map(scoped, & &1["month"]) == oracle["http_scoping"]["scoped_months"]
    assert DetailDigests.yearly(180_101, 2025, []) == {nil, false}
    assert DetailDigests.yearly(180_101, 2025, scoped) == {nil, true}
    assert DetailDigests.yearly(180_101, 2020, scoped) == {nil, false}
    stamp = ~N[2026-10-03 12:00:00]

    Dawarich.Test.StatsSeeds.digest!(180_101, %{
      id: 71,
      year: 2025,
      period_type: 1,
      distance: 888,
      updated_at: stamp
    })

    key = Details.yearly_key(180_101, 2025, stamp)

    for state <- ~w(warm stale_snapshot cached_nil cold) do
      expected = Enum.find(oracle["readers"], &(&1["state"] == state))
      Redis.cache_command(["DEL", key])
      if expected["wire"], do: cache!(key, Base.decode64!(expected["wire"]))
      before = digests()
      {digest, hand_back} = DetailDigests.yearly(180_101, 2025, scoped)
      assert hand_back == (state == "cold")

      assert (digest && digest["distance"]) ==
               if(state == "cold", do: 888, else: expected["distance"])

      assert digests() == before
    end
  end

  test "monthly staleness compares only the selected month and equality stays fresh", %{
    user: user
  } do
    alias Dawarich.Insights.Details.Digests, as: DetailDigests

    oracle =
      Path.expand("../fixtures/a12d1b4/cache.json", __DIR__) |> File.read!() |> Jason.decode!()

    Repo.query!("UPDATE stats SET updated_at=$1 WHERE month=4", [~N[2026-10-04 12:00:00]])
    monthly_digest!(3, ~N[2024-03-01 00:00:00])
    result = Repo.query!("SELECT * FROM stats WHERE user_id=93", [])
    stats = Enum.map(result.rows, &Map.new(Enum.zip(result.columns, &1)))
    before = digests()
    {equal, stale} = DetailDigests.monthly(93, 2024, 3, [3, 4], stats)
    assert stale == oracle["http_scoping"]["monthly_equal_blank"]
    assert equal["travel_patterns"] == %{}
    assert DetailDigests.monthly(93, 2024, 2, [3, 4], stats) == {nil, false}
    assert DetailDigests.monthly(93, 2024, 2, [2, 3, 4], stats) == {nil, true}
    assert digests() == before
    Repo.query!("UPDATE digests SET updated_at=$1 WHERE month=3", [~N[2024-02-01 00:00:00]])
    before = digests()
    {_, stale} = DetailDigests.monthly(93, 2024, 3, [3, 4], stats)
    assert stale == oracle["http_scoping"]["monthly_older"]
    refute elem(DetailDigests.monthly(93, 2024, 3, [], stats), 1)
    assert load(user, %{"year" => "all"}).selected_month == "all"
    assert digests() == before
  end

  test "yearly readers preserve warm stale snapshots cached nil and cold corrupt unavailable hand-back results" do
    oracle =
      Path.expand("../fixtures/a12d1b4/cache.json", __DIR__) |> File.read!() |> Jason.decode!()

    user!(180_101)
    Repo.query!("UPDATE stats SET year=2025 WHERE user_id=180101", [])
    stamp = ~N[2026-10-03 12:00:00]

    Dawarich.Test.StatsSeeds.digest!(180_101, %{
      id: 71,
      year: 2025,
      period_type: 1,
      distance: 777,
      updated_at: stamp,
      travel_patterns: %{"activity_breakdown" => %{"walking" => 1, "flying" => 2}}
    })

    key = Details.yearly_key(180_101, 2025, stamp)
    assert key == hd(oracle["staleness"])["key"]

    for state <- ~w(warm stale_snapshot cached_nil cold corrupt failure) do
      expected = Enum.find(oracle["readers"], &(&1["state"] == state))

      Repo.query!("UPDATE digests SET distance=$1 WHERE id=71", [
        if(state == "stale_snapshot", do: 888, else: 777)
      ])

      assert {:ok, _} = Redis.cache_command(["DEL", key])

      cond do
        expected["wire"] -> cache!(key, Base.decode64!(expected["wire"]))
        state == "corrupt" -> Redis.cache_command(["SET", key, "corrupt fixture"])
        state == "failure" -> stop_supervised!(Dawarich.Redis.Cache)
        true -> :ok
      end

      before = Repo.query!("SELECT * FROM digests ORDER BY id", []).rows

      {digest, hand_back} =
        Dawarich.Insights.Details.Digests.yearly(180_101, 2025, [%{"year" => 2025}])

      assert hand_back == state in ~w(cold corrupt failure)
      assert (digest && digest["distance"]) == expected["distance"]
      pairs = digest && Dawarich.RailsCache.JsonOrder.pattern_pairs(digest).activity_pairs
      assert (pairs && Enum.map(pairs, &Tuple.to_list/1)) == expected["activity_pairs"]
      assert Repo.query!("SELECT * FROM digests ORDER BY id", []).rows == before
    end
  end

  test "a missing yearly digest for a year with stats is Rails' to calculate", %{user: user} do
    monthly_digest!(4, ~N[2024-04-01 00:00:00])
    before = digests()
    page = load(user, %{"year" => "2024", "month" => "4"})
    assert page.rails
    assert page.yearly == nil
    assert digests() == before
  end

  test "a year without stats or digest stays with Phoenix and has no patterns", %{user: user} do
    page = load(user, %{"year" => "2020"})
    refute page.rails
    assert page.yearly == nil
    assert page.time_of_day == %{}
  end

  test "a cold yearly cache entry is Rails' to write; the database digest is kept for rendering",
       %{user: user} do
    yearly_digest!()
    monthly_digest!(4, ~N[2024-04-01 00:00:00])
    page = load(user, %{"year" => "2024", "month" => "4"})
    assert page.rails
    assert page.yearly["id"] == 71

    assert {:ok, nil} =
             Redis.cache_command(["GET", Details.yearly_key(93, 2024, @digest_updated)])
  end

  test "a warm yearly cache entry is used as Rails uses it, even after newer stats",
       %{user: user} do
    yearly_digest!()
    monthly_digest!(4, ~N[2024-04-01 00:00:00])
    warm!()
    Repo.query!("UPDATE stats SET updated_at=$1 WHERE user_id=93", [~N[2026-06-15 09:00:00]])
    Repo.query!("UPDATE digests SET updated_at=$1 WHERE month=4", [~N[2026-06-15 09:00:00]])
    before = digests()
    page = load(user, %{"year" => "2024", "month" => "4"})
    refute page.rails
    assert page.yearly["travel_patterns"] == %{"weekly_pattern" => [1, 2, 3, 4, 5, 6, 7]}
    assert page.monthly["distance"] == 777
    assert digests() == before
  end

  test "a cached nil yearly digest renders without patterns", %{user: user} do
    yearly_digest!()
    monthly_digest!(4, ~N[2024-04-01 00:00:00])
    warm!(<<0, 17, 1, -1.0::little-float-64, -1::little-signed-32, 4, 8, ?0>>)
    page = load(user, %{"year" => "2024", "month" => "4"})
    refute page.rails
    assert page.yearly == nil
  end

  test "a cached value that is not a digest raises, so the gate hands the request to Rails",
       %{user: user} do
    yearly_digest!()
    warm!(<<0, 17, 1, -1.0::little-float-64, -1::little-signed-32, 4, 8, ?i, 86>>)
    assert_raise ArgumentError, fn -> load(user, %{"year" => "2024", "month" => "4"}) end
  end

  test "an unreachable cache is Rails' to answer", %{user: user} do
    yearly_digest!()
    monthly_digest!(4, ~N[2024-04-01 00:00:00])
    stop_supervised!(Dawarich.Redis.Cache)
    assert load(user, %{"year" => "2024", "month" => "4"}).rails
  end

  test "a missing or stale selected month is Rails' to calculate; an unavailable month is read",
       %{user: user} do
    yearly_digest!()
    warm!()
    assert load(user, %{"year" => "2024", "month" => "3"}).rails
    monthly_digest!(3, ~N[2024-02-01 00:00:00])
    assert load(user, %{"year" => "2024", "month" => "3"}).rails
    monthly_digest!(2, ~N[2020-01-01 00:00:00])
    page = load(user, %{"year" => "2024", "month" => "2", "user_id" => "999999"})
    refute page.rails
    assert page.monthly["updated_at"] == ~N[2020-01-01 00:00:00.000000]
    assert page.available_months == [3, 4]
  end

  test "all-time, restricted and coerced years never need a digest", %{user: user} do
    all = load(user, %{"year" => "all"})
    refute all.rails
    assert all.selected_month == "all"
    assert all.totals.distance == 50

    Repo.query!("UPDATE users SET plan=0 WHERE id=93", [])
    restricted = load(%{user | plan: 0}, %{"year" => "2024"})
    refute restricted.rails
    assert restricted.restricted
    refute Map.has_key?(restricted, :totals)

    for raw <- ["", "0", "not-a-year", "1suffix"] do
      page = load(user, %{"year" => raw})
      refute page.rails
      assert page.year == Dawarich.Digests.to_i(raw)
    end

    assert digests() == []
  end

  test "fragments use Rails' six keys, keep warm HTML and are written only when asked",
       %{user: user} do
    page = %{load(user, %{"year" => "2020"}) | top_visits: []} |> Map.put(:country_codes, [])
    first = Fragments.render(user, "en", page, write: false)
    assert map_size(first) == 6

    key =
      "views/insights/details:9efea8724129ec15ede1d72979639af7/93/insights/en/2020//km/location_clusters"

    assert Fragments.key(user, "en", page, "location_clusters") == key
    assert {:ok, nil} = Redis.cache_command(["GET", key])

    Fragments.render(user, "en", page, write: true)
    assert {:ok, ttl} = Redis.cache_command(["PTTL", key])
    assert ttl > 86_390_000 and ttl <= 86_400_000

    changed =
      Map.put(page, :top_visits, [%{name: "New place", visit_count: 9, total_duration: 30}])

    assert Fragments.render(user, "en", changed, write: true) == first

    for {field, value} <- [{:selected_month, 3}, {:unit, "mi"}] do
      refute Fragments.key(user, "en", page, "monthly_digest") ==
               Fragments.key(user, "en", Map.put(page, field, value), "monthly_digest")
    end
  end

  test "fragment keys carry RAILS_CACHE_ID, else RAILS_APP_VERSION, after views as Rails' do",
       %{user: user} do
    saved = Map.new(~w(RAILS_CACHE_ID RAILS_APP_VERSION), &{&1, System.get_env(&1)})

    on_exit(fn ->
      for {name, value} <- saved,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)

    page = load(user, %{"year" => "2020"})
    System.delete_env("RAILS_CACHE_ID")
    System.put_env("RAILS_APP_VERSION", "1.15.2")

    assert Fragments.key(user, "en", page, "travel_patterns") =~
             ~r{\Aviews/1\.15\.2/insights/details:}

    System.put_env("RAILS_CACHE_ID", "c1")
    assert Fragments.key(user, "en", page, "travel_patterns") =~ ~r{\Aviews/c1/insights/details:}
  end

  test "a blank month selects the latest month, as Rails' present? does", %{user: user} do
    yearly_digest!()
    monthly_digest!(4, ~N[2024-04-01 00:00:00])
    warm!()

    for blank <- ["", " ", "\t"] do
      page = load(user, %{"year" => "2024", "month" => blank})
      refute page.rails
      assert page.selected_month == 4
    end
  end
end
