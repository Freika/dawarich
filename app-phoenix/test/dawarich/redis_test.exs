defmodule Dawarich.RedisTest do
  use ExUnit.Case, async: false

  alias Dawarich.Redis

  test "options: explicit database, no sync connect, TLS for rediss" do
    opts = Redis.options("redis://h/3", 1)
    assert opts[:database] == 1
    assert opts[:sync_connect] == false
    refute Keyword.has_key?(opts, :socket_opts)

    assert Keyword.has_key?(Redis.options("rediss://h/3", 1), :socket_opts)
  end

  test "no URL, no child" do
    assert Redis.child_specs(url: nil) == []
    assert Redis.child_specs(url: "") == []
  end

  test "command without a connection returns an error" do
    assert {:error, {:exit, _}} = Redis.command(["PING"], :missing_conn)
  end

  test "the cache connection uses RAILS_CACHE_DB" do
    start_supervised!(hd(Redis.cache_child_specs()))
    assert {:ok, "OK"} = Redis.cache_command(["SET", "wave5b_redis_cache_probe", "v"])

    url = Application.fetch_env!(:dawarich, :redis)[:url]
    {:ok, db0} = Redix.start_link(url, database: 0)
    {:ok, db1} = Redix.start_link(url, database: 1)

    assert Redix.command(db0, ["GET", "wave5b_redis_cache_probe"]) == {:ok, "v"}
    assert Redix.command(db1, ["GET", "wave5b_redis_cache_probe"]) == {:ok, nil}
  end

  test "the Rack::Attack connection reads RACK_ATTACK_REDIS_DB like Rails' throttle store, 3 by default" do
    database = fn ->
      %{start: {Redix, :start_link, [_url, opts]}} = hd(Redis.rack_attack_child_specs())
      opts[:database]
    end

    on_exit(fn -> System.delete_env("RACK_ATTACK_REDIS_DB") end)
    assert Redis.rack_attack_child_specs(url: nil) == []
    assert database.() == 3
    System.put_env("RACK_ATTACK_REDIS_DB", "5")
    assert database.() == 5
    System.put_env("RACK_ATTACK_REDIS_DB", "x")
    assert database.() == 0
    System.delete_env("RACK_ATTACK_REDIS_DB")

    start_supervised!(hd(Redis.rack_attack_child_specs()))
    assert {:ok, "OK"} = Redix.command(Redis.rack_attack(), ["SET", "a9s_rack_attack_probe", "v"])
    url = Application.fetch_env!(:dawarich, :redis)[:url]
    {:ok, db3} = Redix.start_link(url, database: 3)
    assert Redix.command(db3, ["GET", "a9s_rack_attack_probe"]) == {:ok, "v"}
  end

  test "transaction/1 runs MULTI/EXEC on Sidekiq's database" do
    start_supervised!(hd(Redis.child_specs()))
    Redis.command(["DEL", "wave5b_redis_tx_probe_z"])

    assert Redis.transaction([
             ["SET", "wave5b_redis_tx_probe_a", "1"],
             ["ZADD", "wave5b_redis_tx_probe_z", "NX", "5", "m"]
           ]) == {:ok, ["OK", 1]}

    url = Application.fetch_env!(:dawarich, :redis)[:url]
    {:ok, db1} = Redix.start_link(url, database: 1)
    assert Redix.command(db1, ["GET", "wave5b_redis_tx_probe_a"]) == {:ok, "1"}
    assert Redix.command(db1, ["ZSCORE", "wave5b_redis_tx_probe_z", "m"]) == {:ok, "5"}

    stop_supervised!(Redix)
    assert {:error, _} = Redis.transaction([["PING"]])
  end
end
