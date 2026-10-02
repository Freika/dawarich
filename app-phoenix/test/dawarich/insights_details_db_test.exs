defmodule Dawarich.Insights.DetailsDBTest do
  use ExUnit.Case, async: false
  alias Dawarich.{RailsCache, Repo}
  alias Dawarich.Insights.Details
  @now ~U[2026-06-15 10:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    redis_url = Application.fetch_env!(:dawarich, :redis)[:url]
    {:ok, redis} = Redix.start_link(redis_url, database: 1, name: A10DetailsRedis)
    on_exit(fn -> Process.exit(redis, :normal) end)
    user = Dawarich.A10InsightsFixture.seed()
    user = %{id: user["id"], settings: user["settings"], plan: 1}

    namespace =
      "a10-details/" <>
        System.get_env("A10_INSIGHTS_CAPTURE_DIR", "test") <>
        "/" <> Integer.to_string(System.unique_integer([:positive]))

    opts = [
      now: @now,
      self_hosted: false,
      cache: [namespace: namespace, command: fn args -> Redix.command(A10DetailsRedis, args) end]
    ]

    %{user: user, opts: opts}
  end

  test "cold missing yearly refresh precedes weekly projection and selected monthly refresh", %{
    user: user,
    opts: opts
  } do
    page = Details.load(user, %{"year" => "2024", "month" => "4"}, opts)
    assert page.yearly["distance"] == 50_072
    assert page.monthly["distance"] == 12_018
    assert page.weekly == List.duplicate(0, 7)
    assert page.available_months == [3, 4]

    assert page.totals == %{
             distance: 50,
             countries: 2,
             cities: 2,
             countries_list: ["Czechia", "Germany"],
             days: 5,
             biggest_month: %{year: 2024, month: 3, distance: 38}
           }

    assert page.comparison.distance_change == 150
    key = Details.yearly_key(user.id, 2024, page.yearly["updated_at"])
    assert RailsCache.get(key, opts[:cache]) == :miss
    second = Details.load(user, %{"year" => "2024", "month" => "4"}, opts)
    assert second.weekly == [0, 0, 12_018, 0, 0, 0, 0]
    assert {:ok, _} = RailsCache.get(key, opts[:cache])
  end

  test "warm yearly cache skips newer stats, miss recalculates under previous version key", %{
    user: user,
    opts: opts
  } do
    first = Details.load(user, %{"year" => "2024", "month" => "4"}, opts)
    Details.load(user, %{"year" => "2024", "month" => "4"}, opts)

    Repo.query!(
      "UPDATE stats SET distance=distance+1000,updated_at=$2 WHERE user_id=$1 AND year=2024 AND month=3",
      [user.id, ~N[2026-06-15 10:00:02]],
      log: false
    )

    warm =
      Details.load(
        user,
        %{"year" => "2024", "month" => "4"},
        Keyword.put(opts, :now, DateTime.add(@now, 3))
      )

    assert warm.yearly["distance"] == first.yearly["distance"]
    assert warm.totals.distance == 51
    key = Details.yearly_key(user.id, 2024, first.yearly["updated_at"])
    assert {:ok, true} = RailsCache.delete(key, opts[:cache])

    cold =
      Details.load(
        user,
        %{"year" => "2024", "month" => "4"},
        Keyword.put(opts, :now, DateTime.add(@now, 3))
      )

    assert cold.yearly["distance"] == 51_072
    assert {:ok, _} = RailsCache.get(key, opts[:cache])
    assert cold.yearly["updated_at"] == ~N[2026-06-15 10:00:03.000000]
  end

  test "all time and restricted details do not create digests; foreign selectors have no authority",
       %{user: user, opts: opts} do
    all = Details.load(user, %{"year" => "all", "user_id" => "999999"}, opts)
    assert all.selected_month == "all"
    assert all.available_months == []
    assert all.weekly == List.duplicate(0, 7)
    assert all.top_visits == []
    assert all.totals.distance == 70
    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)
    locked = Details.load(%{user | plan: 0}, %{"year" => "2024"}, opts)
    assert locked.year_locked
    refute Map.has_key?(locked, :totals)
    assert Repo.query!("SELECT count(*) FROM digests", [], log: false).rows == [[0]]
  end

  test "unavailable selected month preserves existing digest and confirmed active visits are scoped",
       %{user: user, opts: opts} do
    Repo.query!(
      "INSERT INTO digests(user_id,year,month,period_type,distance,created_at,updated_at) VALUES($1,2024,2,0,777,$2,$2)",
      [user.id, ~N[2020-01-01 00:00:00]],
      log: false
    )

    page = Details.load(user, %{"year" => "2024", "month" => "2", "user_id" => "999999"}, opts)
    assert page.monthly["distance"] == 777
    assert page.monthly["updated_at"] == ~N[2020-01-01 00:00:00.000000]
    assert %{name: "Office", visit_count: 2, total_duration: 240} in page.top_visits
    refute Enum.any?(page.top_visits, &String.contains?(&1.name, "Foreign"))
  end

  test "actual Ruby empty and prefixed year selection includes astronomical year zero", %{
    user: user,
    opts: opts
  } do
    for raw <- ["", "0", "not-a-year", "1suffix"] do
      page = Details.load(user, %{"year" => raw}, opts)
      assert page.year == Dawarich.Digests.to_i(raw)
      assert page.yearly == nil
      assert page.monthly == nil
      assert page.top_visits == []
    end
  end

  test "six real fragment keys retain warm visit HTML, month/unit versions, safe buffers and24hour expiry",
       %{user: user, opts: opts} do
    page = Details.load(user, %{"year" => "2024", "month" => "4"}, opts)
    page = Map.put(page, :country_codes, [])
    first = Dawarich.Insights.Fragments.render(user, "en", page, opts)
    assert map_size(first) == 6

    expected =
      "views/insights/details:9efea8724129ec15ede1d72979639af7/#{user.id}/insights/en/2024/2026-06-15 12:00:00 +0200/km/location_clusters"

    assert Dawarich.Insights.Fragments.key(user, "en", page, "location_clusters", opts) ==
             expected

    assert {:ok, value} = RailsCache.get(expected, opts[:cache])
    assert Dawarich.RailsCache.Snapshot.html(value) == first["location_clusters"]
    key = opts[:cache][:namespace] <> ":" <> expected
    assert {:ok, ttl} = Redix.command(A10DetailsRedis, ["PTTL", key])
    assert ttl > 86_390_000 and ttl <= 86_400_000

    changed =
      Map.put(page, :top_visits, [
        %{name: "New fixture location", visit_count: 100, total_duration: 3000}
      ])

    warm = Dawarich.Insights.Fragments.render(user, "en", changed, opts)
    assert warm == first
    assert warm["location_clusters"] =~ "Office"
    refute warm["location_clusters"] =~ "New fixture location"

    for {field, value} <- [{:selected_month, 3}, {:unit, "mi"}] do
      changed = Map.put(page, field, value)
      before = Dawarich.Insights.Fragments.key(user, "en", page, "monthly_digest", opts)
      after_key = Dawarich.Insights.Fragments.key(user, "en", changed, "monthly_digest", opts)
      refute before == after_key
    end
  end

  test "connected LiveView reads do not repeat GET refresh/cache writes", %{
    user: user,
    opts: opts
  } do
    first = Details.load(user, %{"year" => "2024", "month" => "4"}, opts)
    key = Details.yearly_key(user.id, 2024, first.yearly["updated_at"])

    connected =
      Details.load(user, %{"year" => "2024", "month" => "4"}, Keyword.put(opts, :read_only, true))

    assert connected.yearly["updated_at"] == first.yearly["updated_at"]
    assert connected.monthly["updated_at"] == first.monthly["updated_at"]
    assert RailsCache.get(key, opts[:cache]) == :miss
  end
end
