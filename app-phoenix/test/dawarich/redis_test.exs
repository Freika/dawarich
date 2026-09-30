defmodule Dawarich.RedisTest do
  use ExUnit.Case, async: true

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
end
