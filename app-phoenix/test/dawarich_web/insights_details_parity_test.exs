defmodule DawarichWeb.InsightsDetailsParityTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Insights.{Details, Fragments}
  alias Dawarich.Test.{InsightsSeeds, ParityHTML}

  @dir Path.expand("../fixtures/insights", __DIR__)
  @corpus @dir |> Path.join("details-corpus.json") |> File.read!() |> Jason.decode!()

  setup context do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    InsightsSeeds.start_cache!()

    corpus =
      if context[:overview],
        do: File.read!(Path.join(@dir, "overview-corpus.json")) |> Jason.decode!(),
        else: @corpus

    InsightsSeeds.corpus!(corpus)

    if context[:overview] do
      for point <- corpus["points"] do
        Dawarich.Test.TripsSeeds.point!(%{
          id: point["id"],
          user_id: point["user_id"],
          timestamp: point["timestamp"],
          at: [point["lon"], point["lat"]]
        })

        Dawarich.Repo.query!(
          "UPDATE points SET country_name=$2,city=$3,reverse_geocoded_at=$4 WHERE id=$1",
          [point["id"], point["country_name"], point["city"], ~N[2026-06-15 10:00:00]],
          log: false
        )
      end

      Dawarich.Repo.query!(
        "UPDATE users SET points_count=$1 WHERE id=9601",
        [corpus["points_count"]],
        log: false
      )
    end

    :ok
  end

  @tag :overview
  test "Rails 1.16.0 Insights overview preserves header period summary months tracking years and locked states" do
    corpus = File.read!(Path.join(@dir, "overview-corpus.json")) |> Jason.decode!()

    for request <- corpus["requests"] do
      if request["name"] == "overview-geocoding-en" do
        Dawarich.Test.StatsSeeds.geocoding!()

        Dawarich.Repo.query!(
          "INSERT INTO tracks (id,user_id,start_at,end_at,original_path,created_at,updated_at) VALUES ($1,9601,'2024-03-05 09:00:00','2024-03-05 09:10:00',ST_GeomFromText('LINESTRING(12.3731 51.3397,12.3731 51.3417)',4326),'2026-06-15 10:00:00','2026-06-15 10:00:00')",
          [corpus["track_id"]],
          log: false
        )

        Dawarich.Stats.PointCounts.fetch(9601, true, ~U[2026-06-15 10:00:00Z],
          repo: Dawarich.Repo
        )
      end

      Dawarich.Repo.query!("UPDATE users SET plan=$1 WHERE id=9601", [request["plan"]],
        log: false
      )

      query = URI.decode_query(URI.parse(request["path"]).query)
      scope = Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(9601), query["locale"])

      {:ok, data} =
        Dawarich.Insights.Pages.overview(scope, query,
          now: ~U[2026-06-15 10:00:00Z],
          self_hosted: request["self_hosted"]
        )

      html =
        render_component(&DawarichWeb.InsightsLive.NativeView.render/1,
          live_action: :index,
          data: Map.put(data, :more, false),
          query: query,
          locale: scope.locale,
          page_title: "Insights",
          details: nil,
          residency: nil,
          dialog: nil,
          calendar_mode: "both",
          calendar_country: nil,
          refresh_state: nil
        )

      if data.year_locked do
        assert html =~ "[&_.tooltip:before]:right-0"
      end

      actual = overview_dom(html)
      expected = overview_dom(File.read!(Path.join(@dir, request["name"] <> ".html")))

      if dump = System.get_env("PARITY_DUMP") do
        raw =
          if !data.year_locked && !data.restricted && !data.all_time do
            {:ok, residency} =
              Dawarich.Insights.ResidencyPage.load(scope, query,
                now: ~U[2026-06-15 10:00:00Z],
                self_hosted: request["self_hosted"]
              )

            render_component(&DawarichWeb.InsightsLive.NativeView.render/1,
              live_action: :index,
              data: Map.put(data, :more, false),
              query: query,
              locale: scope.locale,
              page_title: "Insights",
              details: nil,
              residency: %{state: :ready, value: residency},
              dialog: nil,
              calendar_mode: "both",
              calendar_country: nil,
              refresh_state: nil
            )
          else
            html
          end

        File.mkdir_p!(dump)
        File.write!(Path.join(dump, request["name"] <> ".html"), raw)
        File.mkdir_p!(dump)

        File.write!(
          Path.join(dump, request["name"] <> "-actual"),
          inspect(actual, limit: :infinity, pretty: true)
        )

        File.write!(
          Path.join(dump, request["name"] <> "-expected"),
          inspect(expected, limit: :infinity, pretty: true)
        )
      end

      assert actual == expected,
             request["name"] <> ": " <> ParityHTML.first_difference(actual, expected)
    end
  end

  @tag :overview
  test "Rails 1.16.0 residency preserves year calendar ribbon and distance presentation" do
    for locale <- ~w(en de), year <- [2024, 2026, 2022] do
      scope = Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(9601), locale)
      opts = [now: ~U[2026-06-15 10:00:00Z], self_hosted: true]

      {:ok, overview} =
        Dawarich.Insights.Pages.overview(scope, %{"year" => to_string(year)}, opts)

      {:ok, data} =
        Dawarich.Insights.ResidencyPage.load(scope, %{"year" => to_string(year)}, opts)

      html =
        render_component(&DawarichWeb.InsightsLive.NativeParts.residency/1,
          data: data,
          heatmap: overview.heatmap,
          race: overview.consolidated.race,
          locale: locale,
          unit: "km",
          query: %{},
          path: "/insights"
        )

      for row <-
            html
            |> LazyHTML.from_fragment()
            |> LazyHTML.query("[data-testid=insights-distance-row]") do
        assert hd(LazyHTML.attribute(row, "class")) =~ "[&>section]:min-w-0"
      end

      actual = overview_dom(html)
      suffix = if year == 2024, do: locale, else: "#{year}-#{locale}"
      expected = overview_dom(File.read!(Path.join(@dir, "residency-#{suffix}.html")))

      if dump = System.get_env("PARITY_DUMP") do
        File.mkdir_p!(dump)

        File.write!(
          Path.join(dump, "residency-#{locale}-actual"),
          inspect(actual, limit: :infinity, pretty: true)
        )

        File.write!(
          Path.join(dump, "residency-#{locale}-expected"),
          inspect(expected, limit: :infinity, pretty: true)
        )
      end

      assert actual == expected, locale <> ": " <> ParityHTML.first_difference(actual, expected)
    end
  end

  defp overview_dom(html) do
    html
    |> Dawarich.Test.ChartkickHTML.without_charts()
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> overview_nodes()
    |> ParityHTML.normalize()
  end

  defp overview_nodes(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &overview_node/1)

  defp overview_node({tag, attrs, children}) do
    values = Map.new(attrs)

    cond do
      String.starts_with?(values["id"] || "", "chart-year-locked-") ->
        [{tag, Enum.reject(attrs, fn {key, _} -> key == "data-chart" end), []}]

      values["id"] == "stats-count-pending" ->
        assert values["class"] == "sr-only"
        []

      values["id"] in ~w(insights-residency-loading insights-details-loading insights-residency-ready insights-locked) ->
        assert values["class"] in [
                 "contents",
                 "contents [&_.tooltip:before]:left-auto [&_.tooltip:before]:right-0 [&_.tooltip:before]:translate-x-0"
               ]

        overview_nodes(children)

      true ->
        attrs =
          Enum.flat_map(attrs, fn
            {"class", value} ->
              [{"class", String.replace(value, " [&>section]:min-w-0", "")}]

            {key, _} when key in ~w(role aria-label) and tag == "i" ->
              assert Map.has_key?(values, "data-date")
              assert values["role"] == "img" && values["aria-label"] != ""
              []

            {"id", id} when id in ~w(insights-upgrade insights-update) ->
              []

            {"href", "/auth/dawarich?" <> _} ->
              [{"href", "#"}]

            {"data-empty", _} ->
              []

            {"id", "stats-count-ready"} ->
              []

            {"onclick", value}
            when value in ["countries_visited.showModal()", "cities_visited.showModal()"] ->
              []

            {"data-url", value} ->
              assert String.starts_with?(value, "/insights/routes/")
              []

            {"data-style", value} ->
              assert value == "light"
              []

            pair ->
              [pair]
          end)

        [{tag, attrs, overview_nodes(children)}]
    end
  end

  defp overview_node(other), do: [other]

  test "fragments are keyed with the template digest Rails renders insights/details with" do
    data = %{selected: 2024, max_stat_updated: nil, unit: "km"}
    key = Fragments.key(%{id: 1, settings: %{}}, "en", data, "travel_patterns")
    assert String.starts_with?(key, "views/" <> @corpus["template_digest"] <> "/")
  end

  @parts ~w(year_comparison activity_breakdown location_clusters monthly_digest travel_patterns movement_wellness)

  test "Rails 1.16.0 insights details preserves card grid and chart containers" do
    for request <- @corpus["requests"] do
      query = request["path"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      user = Dawarich.Accounts.get(request["user_id"])
      scope = Dawarich.Accounts.Scope.for_user(user, query["locale"] || "en")

      {:ok, data} =
        DawarichWeb.InsightsLive.NativePage.details(scope, {query, [self_hosted: false]})

      html =
        render_component(&DawarichWeb.InsightsLive.NativeParts.details/1,
          data: data,
          locale: scope.locale,
          query: query,
          path: "/insights/details"
        )

      rails = File.read!(Path.join(@dir, request["fixture"]))
      actual = details_dom(html)
      expected = details_dom(rails)

      assert actual == expected,
             request["fixture"] <> ": " <> ParityHTML.first_difference(actual, expected)
    end
  end

  test "monthly source links patch their owning overview or direct response document" do
    scope = Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(9601), "en")

    {:ok, data} =
      DawarichWeb.InsightsLive.NativePage.details(
        scope,
        {%{"year" => "2024", "month" => "4"}, [self_hosted: true]}
      )

    for path <- ["/insights", "/insights/details"] do
      html =
        render_component(&DawarichWeb.InsightsLive.NativeParts.details/1,
          data: data,
          locale: "en",
          query: %{},
          path: path
        )

      links =
        html |> LazyHTML.from_fragment() |> LazyHTML.query("a[href^='/insights/details?month=']")

      assert Enum.count(links) > 0

      for link <- links do
        [href] = LazyHTML.attribute(link, "href")
        clicks = LazyHTML.attribute(link, "phx-click")
        assert length(clicks) == 1
        assert [["patch", %{"href" => target}]] = Jason.decode!(hd(clicks))
        assert target == path <> "?" <> URI.parse(href).query
      end
    end
  end

  test "direct Insights details stay in one full-width application flex child" do
    html =
      render_component(&DawarichWeb.InsightsLive.NativeDirect.render/1,
        data: %{restricted: true},
        details: nil,
        locale: "en",
        query: %{}
      )

    dom = LazyHTML.from_fragment(html)

    assert Enum.count(LazyHTML.query(dom, "#native-insights-details.w-full > #insights-locked")) ==
             1

    assert Enum.count(LazyHTML.query(dom, "#native-insights-details > #insights-locked > div")) ==
             2
  end

  test "direct native Insights details preserves the source response without overview controls" do
    request = hd(@corpus["requests"])
    query = request["path"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    user = Dawarich.Accounts.get(request["user_id"])
    scope = Dawarich.Accounts.Scope.for_user(user, "en")
    {:ok, data} = Dawarich.Insights.Pages.overview(scope, query, self_hosted: true)

    {:ok, details} =
      DawarichWeb.InsightsLive.NativePage.details(scope, {query, [self_hosted: true]})

    html =
      render_component(&DawarichWeb.InsightsLive.NativeView.render/1,
        data: data,
        details: %{state: :ready, value: details},
        residency: nil,
        locale: "en",
        query: query,
        live_action: :details,
        dialog: nil,
        refresh_state: nil,
        page_title: "Insights",
        calendar_mode: "both",
        calendar_country: nil
      )

    actual = details_dom(html)
    expected = details_dom(File.read!(Path.join(@dir, request["fixture"])))
    assert actual == expected, ParityHTML.first_difference(actual, expected)

    loading =
      render_component(&DawarichWeb.InsightsLive.NativeDirect.render/1,
        data: data,
        details: nil,
        locale: "en",
        query: query
      )

    assert loading
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#insights-details-loading[role=status]")
           |> Enum.count() == 1
  end

  defp details_dom(html) do
    html
    |> Dawarich.Test.ChartkickHTML.without_charts()
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> details_nodes()
    |> ParityHTML.normalize()
  end

  defp details_nodes(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &details_node/1)

  defp details_node({"section", attrs, children}) do
    assert Map.new(attrs)["id"] in ~w(insights-details-ready insights-details-pending)
    assert Map.new(attrs)["class"] == "contents"
    details_nodes(children)
  end

  defp details_node({"div", attrs, children}) do
    if Map.new(attrs)["id"] == "native-insights-details" do
      assert Map.new(attrs)["class"] == "w-full"
      details_nodes(children)
    else
      if Map.new(attrs)["id"] == "chart-1" do
        [{"div", Enum.reject(attrs, fn {key, _} -> key == "data-chart" end), []}]
      else
        [{"div", attrs, details_nodes(children)}]
      end
    end
  end

  defp details_node({tag, attrs, children}), do: [{tag, attrs, details_nodes(children)}]
  defp details_node(other), do: [other]

  test "fresh and persisted activity preserve source corpus order" do
    for {state, order} <- [
          {"fresh", ~w(walking stationary flying)},
          {"persisted", ~w(flying walking stationary)}
        ] do
      values = %{
        "walking" => %{"duration" => 600, "percentage" => 14},
        "stationary" => %{"duration" => 1800, "percentage" => 43},
        "flying" => %{"duration" => 1800, "percentage" => 43}
      }

      patterns = %Jason.OrderedObject{
        values: [
          {"activity_breakdown", %Jason.OrderedObject{values: Enum.map(order, &{&1, values[&1]})}}
        ]
      }

      data =
        Dawarich.RailsCache.JsonOrder.pattern_pairs(%{
          "_rails_json" => %{"travel_patterns" => Jason.encode!(patterns)}
        })
        |> Map.put(:activity, values)

      actual =
        render_component(&DawarichWeb.InsightsDetails.Activity.render/1, %{
          locale: "en",
          data: data
        })

      expected = File.read!(Path.join(@dir, "activity-#{state}.html"))
      assert ParityHTML.normalize(actual) == ParityHTML.normalize(expected)
    end
  end

  for state <- [:warm, :stale, nil, :cold] do
    @cache_state state
    test "native Insights #{inspect(state)} cache state preserves corpus values without inline calculation" do
      before =
        Dawarich.Repo.query!("SELECT id,updated_at FROM digests ORDER BY id", [], log: false).rows

      for request <- @corpus["requests"], do: native_values(request, @cache_state)

      assert Dawarich.Repo.query!("SELECT id,updated_at FROM digests ORDER BY id", [], log: false).rows ==
               before

      assert Dawarich.Repo.query!("SELECT count(*) FROM phoenix.rails_commands", [], log: false).rows ==
               [[0]]
    end
  end

  for request <- @corpus["requests"] do
    @request request
    test "Phoenix keys the fragments of #{request["path"]} exactly as Rails wrote them" do
      %{"settings" => settings, "plan" => plan} =
        Enum.find(@corpus["users"], &(&1["id"] == @request["user_id"]))

      user = %{id: @request["user_id"], settings: settings, plan: plan}
      query = @request["path"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      data = Details.load(user, query, self_hosted: false)
      keys = for name <- @parts, do: Fragments.key(user, query["locale"] || "en", data, name)
      assert Enum.sort(keys) == Enum.sort(@request["fragment_keys"])
    end

    test "native #{@request["path"]} preserves scoped source totals localized patterns and chart values" do
      native_values(@request)
    end
  end

  defp native_values(request, state \\ :cold) do
    query = request["path"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    user = Dawarich.Accounts.get(request["user_id"])
    scope = Dawarich.Accounts.Scope.for_user(user, query["locale"] || "en")

    {:ok, cache} = Dawarich.Test.NativePageCache.start()

    opts =
      Dawarich.Test.NativePageCache.options(cache)
      |> Keyword.merge(
        self_hosted: false,
        now: DateTime.from_unix!(Dawarich.Test.NativePageCache.now(cache))
      )

    source = Details.load(user, query, self_hosted: false, fill: false)
    assert {:ok, seed} = DawarichWeb.InsightsLive.NativePage.details(scope, {query, opts})
    assert seed.state == :ready
    [key] = Map.keys(Dawarich.Test.NativePageCache.entries(cache))
    assert String.starts_with?(key, "dawarich:native:data:v1:")

    assert Enum.any?(
             Dawarich.Test.NativePageCache.commands(cache),
             &match?(["SET", ^key, _, "EX", "3600"], &1)
           )

    case state do
      :warm ->
        :ok

      :stale ->
        {:ok, bytes} =
          Dawarich.Cache.PagesCodec.encode(%{
            schema: 1,
            expires_at: Dawarich.Test.NativePageCache.now(cache) - 1,
            value: %{seed | weekly: [999_999]}
          })

        Dawarich.Test.NativePageCache.corrupt(cache, key, bytes)

      nil ->
        {:ok, bytes} = Dawarich.Cache.PagesCodec.encode(nil)
        Dawarich.Test.NativePageCache.corrupt(cache, key, bytes)

      :cold ->
        Dawarich.Test.NativePageCache.command(cache, ["UNLINK", key])
    end

    before_gets =
      Enum.count(Dawarich.Test.NativePageCache.commands(cache), &match?(["GET", _], &1))

    {{:ok, data}, queries} =
      Dawarich.Test.NativeAdminUI.queries(fn ->
        DawarichWeb.InsightsLive.NativePage.details(scope, {query, opts})
      end)

    assert Enum.count(Dawarich.Test.NativePageCache.commands(cache), &match?(["GET", ^key], &1)) ==
             before_gets + 1

    reads =
      Enum.count(
        queries,
        &String.contains?(&1, "SELECT year,month,distance,toponyms,daily_distance")
      )

    assert reads == if(state == :warm, do: 0, else: 1)
    refute Enum.any?(queries, &Regex.match?(~r/\b(INSERT|UPDATE|DELETE)\b/i, &1))
    assert data == seed
    assert data.restricted == source.restricted
    assert data.year == source.year
    assert data.unit == source.unit

    if !data.restricted do
      assert Map.take(data.totals, [:distance, :countries, :cities, :days, :biggest_month]) ==
               Map.take(source.totals, [:distance, :countries, :cities, :days, :biggest_month])

      assert data.weekly == source.weekly
      assert data.time_of_day == source.time_of_day
      assert data.seasonality == source.seasonality
      assert data.activity == source.activity

      html =
        render_component(&DawarichWeb.InsightsLive.NativeParts.details/1, %{
          data: data,
          locale: scope.locale,
          query: query,
          path: "/insights/details"
        })

      refute html =~ "turbo-frame"
      refute html =~ "Chartkick"

      assert html |> LazyHTML.from_document() |> LazyHTML.text() =~
               DawarichWeb.Translate.t(
                 scope.locale,
                 "insights.activity_breakdown.activity_breakdown",
                 %{}
               )

      if data.monthly do
        assert data.monthly.distance == source.monthly["distance"]
        assert data.monthly.distances == source.monthly["monthly_distances"]

        [raw] =
          html
          |> LazyHTML.from_document()
          |> LazyHTML.query("#chart-1")
          |> LazyHTML.attribute("data-chart")

        assert Jason.decode!(raw)["data"] ==
                 DawarichWeb.InsightsDetails.MonthFormat.chart(
                   scope.locale,
                   source.monthly,
                   source.unit
                 )
      end

      assert {:ok, _} = Dawarich.Cache.PagesCodec.encode(data)
    end

    assert :ok = ExUnit.Callbacks.stop_supervised(Agent)
  end
end
