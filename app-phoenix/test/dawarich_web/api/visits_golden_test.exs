defmodule DawarichWeb.Api.VisitsGoldenTest do
  use Dawarich.ApiEndpointCase
  use Dawarich.JobsCase, async: false

  alias Dawarich.Test.ApiGolden

  @golden "test/fixtures/api_visits/golden.json" |> File.read!() |> Jason.decode!()
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

  for kase <- @golden["cases"] do
    @kase kase
    @setup_rows @golden["setups"][kase["setup"]]
    @tag golden_case: String.to_atom(kase["name"])
    test "golden #{kase["name"]}", %{port: port, upstream: upstream} do
      Dawarich.FixtureCleanup.delete!(ScratchRepo, @tables)
      for {name, value} <- @kase["env"], do: System.put_env(name, value)

      for [table, seeds] <- @setup_rows, row <- seeds do
        assert table in @tables
        ApiGolden.insert!(table, row, ScratchRepo)
        if table == "users", do: ApiGolden.insert!(table, row)
      end

      for {name, value} <- @sequences,
          do: rows("SELECT setval($1::text::regclass,$2,false)", [name, value])

      for {key, _} <- @kase["cache_after"], do: Dawarich.Redis.cache_command(["DEL", key])

      primed_at = System.monotonic_time(:millisecond)

      for {key, _} <- @kase["cache_after"],
          String.starts_with?(key, "timeline_month_summary/"),
          do: assert(Dawarich.RailsCache.put(key, "primed", expires_in: 300) == {:ok, "OK"})

      before = after_rows()
      ApiGolden.check(@kase, port, upstream)
      assert after_rows() == if(@kase["expect"] == "own", do: @kase["after"], else: before)
      effects = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")

      if @kase["expect"] != "own" || @kase["response"]["status"] >= 400 ||
           @kase["request"]["method"] == "GET",
         do: assert(effects == [])

      assert_jobs(effects, @kase["jobs_after"] || [])
      assert_months(effects, @kase, primed_at)
      for {key, _} <- @kase["cache_after"], do: Dawarich.Redis.cache_command(["DEL", key])
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
    for {key, _} <- kase["cache_after"] do
      timeline? = String.starts_with?(key, "timeline_month_summary/")
      assert Dawarich.RailsCache.get(key) == if(timeline?, do: {:ok, "primed"}, else: :miss)
      assert {:ok, ttl} = Dawarich.Redis.cache_command(["TTL", key])
      elapsed = (System.monotonic_time(:millisecond) - primed_at) / 1_000

      assert if(timeline?,
               do: ttl > 0 and ttl <= 300 and ttl >= 300 - ceil(elapsed),
               else: ttl == -2
             )
    end

    if kase["expect"] == "own" do
      keys =
        for {key, %{"value" => nil}} <- kase["cache_after"],
            String.starts_with?(key, "timeline_month_summary/"),
            do: key

      targeted =
        for ["visit_months_changed", payload] <- effects,
            at <- payload["started_at"],
            {key, _} <- kase["cache_after"],
            String.starts_with?(key, "timeline_month_summary/"),
            [_prefix, owner, month | suffix] = String.split(key, "/"),
            zone = suffix |> Enum.drop(-2) |> Enum.join("/"),
            String.to_integer(owner) == payload["user_id"],
            month == month(at, zone),
            do: key

      assert Enum.sort(Enum.uniq(targeted)) == Enum.sort(keys)
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
