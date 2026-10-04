defmodule Dawarich.Auth.RegistrationSettingRedisTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.Auth.RegistrationSetting
  alias Dawarich.Redis

  test "a cache Redis that never answers costs the read about one second, as in Rails" do
    sink = listen()

    start_supervised!({Redix, {"redis://127.0.0.1:#{sink.port}", [name: Redis.Cache]}})

    socket = accept(sink)
    {elapsed, result} = :timer.tc(fn -> RegistrationSetting.fetch(%{}) end)
    :gen_tcp.close(socket)

    assert result == :error
    assert elapsed >= 900_000
    assert elapsed < 3_000_000
  end
end
