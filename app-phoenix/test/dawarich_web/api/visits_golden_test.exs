defmodule DawarichWeb.Api.VisitsGoldenTest do
  use Dawarich.ApiEndpointCase
  @moduletag api_golden: true
  use Dawarich.JobsCase, async: false

  alias Dawarich.Test.ApiGolden

  @golden "test/golden_captures/api_visits.json" |> File.read!() |> Jason.decode!()
  @now @golden["now"] |> DateTime.from_iso8601() |> elem(1)
  @moduletag api_now: @now
  @moduletag api_public_only: true
  @moduletag :capture_log
  @tables ~w(users areas places visits points place_visits notes tags taggings instance_settings)
  @after_tables @tables -- ["users"]
  @sequences @golden["sequences"]

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    previous = System.get_env("STORE_GEODATA")
    System.delete_env("STORE_GEODATA")

    on_exit(fn ->
      if previous,
        do: System.put_env("STORE_GEODATA", previous),
        else: System.delete_env("STORE_GEODATA")
    end)

    :ok
  end

  test "timeline cache TTL accounts for elapsed time" do
    key = "timeline_month_summary/ttl_regression"
    primed_at = System.monotonic_time(:millisecond) - 3_000
    assert {:ok, "OK"} = Dawarich.RailsCache.put(key, "primed", expires_in: 300)
    assert {:ok, 1} = Dawarich.Redis.cache_command(["PEXPIRE", key, "297000"])
    kase = %{"cache_after" => %{key => %{}}, "expect" => "rails"}
    assert_months([], kase, primed_at)

    for ttl <- [290_000, 301_000] do
      assert {:ok, 1} = Dawarich.Redis.cache_command(["PEXPIRE", key, to_string(ttl)])
      assert_raise ExUnit.AssertionError, fn -> assert_months([], kase, primed_at) end
    end

    Dawarich.Redis.cache_command(["DEL", key])
  end

  setup_all do
    {:ok, golden: File.read!("test/golden_captures/api_visits.json") |> Jason.decode!()}
  end

  for kase <- @golden["cases"] do
    @tag golden_case: String.to_atom(kase["name"])
    @case_name kase["name"]
    test "golden #{kase["name"]}", %{port: port, upstream: upstream, golden: golden} do
      kase = Enum.find(golden["cases"], &(&1["name"] == @case_name))
      Dawarich.FixtureCleanup.delete!(ScratchRepo, @tables)
      for {name, value} <- kase["env"], do: System.put_env(name, value)

      for [table, seeds] <- golden["setups"][kase["setup"]], row <- seeds do
        assert table in @tables
        ApiGolden.insert!(table, row, ScratchRepo)
        if table == "users", do: ApiGolden.insert!(table, row)
      end

      for {name, value} <- @sequences,
          do: rows("SELECT setval($1::text::regclass,$2,false)", [name, value])

      for {key, _} <- kase["cache_after"], do: Dawarich.Redis.cache_command(["DEL", key])

      primed_at = System.monotonic_time(:millisecond)

      for {key, _} <- kase["cache_after"],
          String.starts_with?(key, "timeline_month_summary/"),
          do: assert(Dawarich.RailsCache.put(key, "primed", expires_in: 300) == {:ok, "OK"})

      if response = kase["provider_response"] do
        start_supervised!(Dawarich.Geocoding.FakeHttp)
        start_supervised!(hd(Dawarich.Redis.child_specs()))
        config = Dawarich.Geocoding.Config.resolve(ScratchRepo)

        {url, response_key, _} =
          Dawarich.Geocoding.Query.build(
            config,
            {52.52, 13.405},
            [limit: 10, radius: 0.5, distance_sort: true],
            Dawarich.AppVersion.current()
          )

        Dawarich.TtlCache.delete({Dawarich.Geocoding.ResponseCache, response_key})
        Dawarich.Geocoding.FakeHttp.stub(url, 200, response)
      end

      ApiGolden.check(kase, port, upstream)

      if kase["provider_response"],
        do: assert(length(Dawarich.Geocoding.FakeHttp.requests()) == 1)

      assert after_rows() == Map.fetch!(kase, "after")
      effects = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")

      if kase["response"]["status"] >= 400 ||
           kase["request"]["method"] == "GET",
         do: assert(effects == [])

      assert_jobs(effects, kase["jobs_after"] || [])
      assert_months(effects, kase, primed_at)
      for {key, _} <- kase["cache_after"], do: Dawarich.Redis.cache_command(["DEL", key])
    end
  end

  defp after_rows do
    Map.new(@after_tables, fn table ->
      data = rows("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
      {table, Enum.map(data, fn [text] -> Jason.decode!(text) end)}
    end)
  end

  defp assert_jobs(effects, jobs) do
    actual =
      Enum.flat_map(effects, fn
        ["places_delete_if_orphan", %{"place_ids" => ids}] ->
          Enum.map(ids, &%{"job" => "Places::DeleteIfOrphanJob", "args" => [&1]})

        ["place_name_fetch", %{"place_id" => id}] ->
          [%{"job" => "Places::NameFetchingJob", "args" => [id]}]

        ["visit_months_changed", _] ->
          []
      end)

    assert Enum.sort(actual) == Enum.sort(jobs)
  end

  defp assert_months(effects, kase, primed_at) do
    payloads =
      rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Points.VisitMonthsWorker'")

    targeted =
      for [payload] <- payloads,
          at <- payload["started_at"],
          {key, _} <- kase["cache_after"],
          String.starts_with?(key, "timeline_month_summary/"),
          [_prefix, owner, month | suffix] = String.split(key, "/"),
          zone = suffix |> Enum.drop(-2) |> Enum.join("/"),
          String.to_integer(owner) == payload["user_id"],
          month == month(at, zone),
          do: key

    targeted = Enum.sort(Enum.uniq(targeted))

    for {key, _} <- kase["cache_after"] do
      timeline? = String.starts_with?(key, "timeline_month_summary/")

      invalidated? =
        Enum.any?(payloads, fn [payload] ->
          String.starts_with?(key, "timeline_month_summary/#{payload["user_id"]}/")
        end)

      readable? = timeline? and key not in targeted and not invalidated?

      if String.starts_with?(key, "places_nearby:") and kase["provider_response"] do
        assert Dawarich.Photos.ProviderCache.get(key) == {:ok, kase["cache_after"][key]["value"]}
      else
        assert Dawarich.RailsCache.get(key) == if(readable?, do: {:ok, "primed"}, else: :miss)
      end

      assert {:ok, ttl} = Dawarich.Redis.cache_command(["TTL", key])
      elapsed = (System.monotonic_time(:millisecond) - primed_at) / 1_000

      assert if(timeline?,
               do: ttl > 0 and ttl <= 300 and ttl >= 300 - ceil(elapsed),
               else:
                 if(String.starts_with?(key, "places_nearby:") and kase["provider_response"],
                   do: ttl > 0 and ttl <= 3600,
                   else: ttl == -2
                 )
             )
    end

    if Map.has_key?(kase, "after") do
      keys =
        for {key, %{"value" => value}} <- kase["cache_after"],
            String.starts_with?(key, "timeline_month_summary/"),
            value == nil or
              (kase["name"] in ~w(bulk_decline bulk_partial destroy_demo) and
                 String.contains?(key, "/2026-09/")),
            do: key

      assert targeted == Enum.sort(keys)
      reverse = for ["visit_months_changed", payload] <- effects, do: payload
      assert Enum.sort(reverse) == Enum.sort(List.flatten(payloads))
    else
      assert targeted == []
    end
  end

  defp month(at, zone) do
    {:ok, at, _} = DateTime.from_iso8601(at)

    [[month]] =
      rows("SELECT to_char($1::timestamp AT TIME ZONE 'UTC' AT TIME ZONE $2,'YYYY-MM')", [
        DateTime.to_naive(at),
        zone
      ])

    month
  end
end
