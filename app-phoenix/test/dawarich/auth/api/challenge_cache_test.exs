defmodule Dawarich.Auth.Api.ChallengeCacheTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.Api.ChallengeCache
  alias Dawarich.{RailsCache.Wire, Redis}
  @rows "test/fixtures/auth/api_auth/cache.json" |> File.read!() |> Jason.decode!()
  @now ~U[2026-10-04 12:00:00Z]

  setup do
    for spec <- Redis.cache_child_specs() ++ Redis.child_specs(), do: start_supervised!(spec)
    jti = Ecto.UUID.generate()
    key = "otp_challenge:consumed:" <> jti
    assert {:ok, nil} = Redis.cache_command(["GET", key])

    on_exit(fn ->
      config = Application.fetch_env!(:dawarich, :redis)
      {:ok, conn} = Redix.start_link(config[:url], database: config[:cache_database])
      Redix.command(conn, ["DEL", key])
      GenServer.stop(conn)
    end)

    %{jti: jti, key: key, context: %{clock: fn -> @now end}}
  end

  test "OTP consumed markers match source existence NX encoding and post-consumption expiry", c do
    for row <- @rows, row["name"] in ~w(true false nil corrupt expired) do
      bytes = Base.decode64!(row["wire_base64"])
      assert {:ok, "OK"} = Redis.cache_command(["SET", c.key, bytes, "PX", "300000"])

      if row["name"] == "corrupt" do
        assert {:replay, _} = ChallengeCache.exists?(c.jti, c.context)
      else
        assert {:ok, exists} = ChallengeCache.exists?(c.jti, c.context)
        assert exists == row["exists"]
      end

      assert {:ok, nil} = Redis.command(["GET", c.key])
    end

    for value <- [true, false, nil] do
      bytes = Wire.encode_boolean(value, expires_at: DateTime.to_unix(@now) + 300)
      assert {:ok, "OK"} = Redis.cache_command(["SET", c.key, bytes, "PX", "200000"])
      assert {:ok, ttl} = Redis.cache_command(["PTTL", c.key])
      assert ChallengeCache.mark(c.jti, c.context) == false
      assert {:ok, retained} = Redis.cache_command(["GET", c.key])
      assert retained == bytes
      assert {:ok, after_ttl} = Redis.cache_command(["PTTL", c.key])
      assert after_ttl <= ttl and after_ttl >= ttl - 1000
    end

    Redis.cache_command(["DEL", c.key])
    assert {:ok, false} = ChallengeCache.exists?(c.jti, c.context)
    late = %{c.context | clock: fn -> DateTime.add(@now, 299) end}
    assert ChallengeCache.mark(c.jti, late) == true
    assert {:ok, bytes} = Redis.cache_command(["GET", c.key])
    source = Enum.find(@rows, &(&1["name"] == "late-consumption-nx"))
    assert bytes == Base.decode64!(source["wire_base64"])
    assert {:ok, %{value: true, expires_at: expires}} = Wire.decode(bytes)
    assert expires == DateTime.to_unix(@now) + 599
    assert {:ok, ttl} = Redis.cache_command(["PTTL", c.key])
    assert ttl in 299_000..300_000
    assert {:ok, true} = ChallengeCache.exists?(c.jti, late)

    assert {:ok, false} =
             ChallengeCache.exists?(c.jti, %{c.context | clock: fn -> DateTime.add(@now, 600) end})

    unavailable = Map.put(c.context, :cache_command, fn _ -> {:error, :unavailable} end)
    assert {:replay, _} = ChallengeCache.exists?(c.jti, unavailable)
    assert ChallengeCache.mark(c.jti, unavailable) == nil
  end
end
