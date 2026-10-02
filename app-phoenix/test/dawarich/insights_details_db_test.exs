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
end
