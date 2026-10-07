Code.require_file("support.exs", __DIR__)

defmodule Dawarich.Tracks.MapMatching.CacheRefreshTest do
  use Dawarich.TracksCase, async: false
  alias Dawarich.Experimental
  alias Dawarich.MapMatching.TestSupport
  alias Dawarich.Tracks.MapMatching.{State, Sweeper}

  setup do
    TestSupport.setup!()
    saved = Map.new(~w(MAP_MATCHING_ENABLED ATLAS_URL), &{&1, System.get_env(&1)})
    Enum.each(Map.keys(saved), &System.delete_env/1)
    setting!("atlas_url", "http://atlas.example.invalid")

    on_exit(fn ->
      Enum.each(saved, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  for {from, to, tag} <- [{false, true, :r3_off_on}, {true, false, :r3_on_off}] do
    @tag tag
    test "R3 #{from} to #{to} converges after Rails TTL with one refresher and zero fresh queries" do
      from = unquote(from)
      to = unquote(to)
      setting!("map_matching_enabled", from)
      assert Experimental.refresh_map_matching(ScratchRepo) == from
      setting!("map_matching_enabled", to)
      observe_queries!(true)

      age!(29_000)
      for _ <- 1..32, do: assert(Experimental.cached_map_matching?(ScratchRepo) == from)
      refute_receive {:settings_query, _}, 50

      age!(30_001)
      assert Experimental.cached_map_matching?(ScratchRepo) == from
      assert_receive {:settings_query, refresher}, 1000

      try do
        readers =
          for _ <- 1..32, do: Task.async(fn -> Experimental.cached_map_matching?(ScratchRepo) end)

        assert Enum.map(readers, &Task.await/1) == List.duplicate(from, 32)
        refute_receive {:settings_query, _}, 50
      after
        send(refresher, :release)
      end

      await_value!(to)
      for _ <- 1..32, do: assert(Experimental.cached_map_matching?(ScratchRepo) == to)
      refute_receive {:settings_query, _}, 50
    end
  end

  for {from, to, tag} <- [{false, true, :r3_sweep_on}, {true, false, :r3_sweep_off}] do
    @tag tag
    test "R3 sweeper refreshes a stale #{from} cache to #{to} and preserves recovery" do
      from = unquote(from)
      to = unquote(to)
      track = TestSupport.input!(ScratchRepo)
      setting!("map_matching_enabled", from)
      assert Experimental.refresh_map_matching(ScratchRepo) == from
      setting!("map_matching_enabled", to)
      age!(30_001)

      assert :ok = Sweeper.run(ScratchRepo)
      assert Experimental.cached_map_matching?(ScratchRepo) == to
      assert State.read(ScratchRepo, track.id).status == if(to, do: :pending, else: nil)
      assert length(TestSupport.jobs(ScratchRepo, track.id)) == if(to, do: 1, else: 0)
    end
  end

  defp age!(milliseconds) do
    [entry] = :ets.lookup(Experimental, ScratchRepo)

    :ets.insert(
      Experimental,
      put_elem(entry, 2, System.monotonic_time(:millisecond) - milliseconds)
    )
  end

  defp observe_queries!(hold) do
    handler = {__MODULE__, make_ref()}
    parent = self()
    event = ScratchRepo.config()[:telemetry_prefix] ++ [:query]
    :ok = :telemetry.attach(handler, event, &__MODULE__.query/4, {parent, hold})
    on_exit(fn -> :telemetry.detach(handler) end)
  end

  def query(_, _, meta, {parent, hold}) do
    if String.starts_with?(to_string(meta.query), "SELECT") and
         String.contains?(to_string(meta.query), "instance_settings") do
      send(parent, {:settings_query, self()})
      if hold, do: receive(do: (:release -> :ok))
    end
  end

  defp await_value!(value, remaining \\ 200)
  defp await_value!(_, 0), do: flunk("cache refresh did not publish")

  defp await_value!(value, remaining) do
    if Experimental.cached_map_matching?(ScratchRepo) != value do
      Process.sleep(5)
      await_value!(value, remaining - 1)
    end
  end

  defp setting!(key, value) do
    rows(
      "INSERT INTO instance_settings(key,value,created_at,updated_at) VALUES($1,$2,now(),now()) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
      [key, value]
    )
  end
end
