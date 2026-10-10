defmodule DawarichWeb.InsightsDetailsParityTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Insights.{Details, Fragments}
  alias Dawarich.Test.{InsightsSeeds, ParityHTML}

  @dir Path.expand("../fixtures/insights", __DIR__)
  @corpus @dir |> Path.join("details-corpus.json") |> File.read!() |> Jason.decode!()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    InsightsSeeds.start_cache!()
    InsightsSeeds.corpus!(@corpus)

    :ok
  end

  test "fragments are keyed with the template digest Rails renders insights/details with" do
    data = %{selected: 2024, max_stat_updated: nil, unit: "km"}
    key = Fragments.key(%{id: 1, settings: %{}}, "en", data, "travel_patterns")
    assert String.starts_with?(key, "views/" <> @corpus["template_digest"] <> "/")
  end

  @parts ~w(year_comparison activity_breakdown location_clusters monthly_digest travel_patterns movement_wellness)

  test "warm nil stale and cold details preserve the source corpus values and order" do
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

    before = Dawarich.Repo.query!("SELECT id,updated_at FROM digests ORDER BY id", []).rows

    for request <- @corpus["requests"], state <- [:warm, :stale, nil, :cold] do
      for fragment <- request["fragment_keys"],
          do: Dawarich.Redis.cache_command(["DEL", fragment])

      native_values(request, state)

      assert Dawarich.Repo.query!("SELECT id,updated_at FROM digests ORDER BY id", []).rows ==
               before
    end

    assert Dawarich.Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
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

    [[updated]] =
      Dawarich.Repo.query!(
        "SELECT updated_at FROM digests WHERE user_id=$1 AND year=2024 AND period_type=1",
        [user.id]
      ).rows

    key = Details.yearly_key(user.id, 2024, updated)
    Dawarich.Redis.cache_command(["DEL", key])
    source = Details.load(user, query, self_hosted: false, fill: false)
    entry = Enum.find(@corpus["cache"], &String.contains?(&1["key"], "/#{user.id}/"))

    case state do
      :warm ->
        InsightsSeeds.cache!(key, Base.decode64!(entry["wire"]))

      :stale ->
        Dawarich.Redis.cache_command(["SET", key, "corrupt source cache"])

      nil ->
        InsightsSeeds.cache!(key, Dawarich.RailsCache.Wire.encode_boolean(nil, expires_at: nil))

      :cold ->
        Dawarich.Redis.cache_command(["DEL", key])
    end

    {:ok, data} = Dawarich.Insights.Pages.details(scope, query, self_hosted: false)
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
          |> LazyHTML.query("#insights-monthly-chart")
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
  end
end
