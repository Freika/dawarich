defmodule Dawarich.Places.NearbyInputTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias Dawarich.{Places, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.FrameSeeds, as: S
  @params %{"latitude" => "51.0", "longitude" => "12.0"}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{scope: Scope.for_user(S.user!(11841), "en")}
  end

  test "native nearby retains defaults zero island and provider fallbacks", ctx do
    fetch = fn _, lat, lon, radius, limit, _ ->
      send(self(), {:provider, lat, lon, radius, limit})
      []
    end

    assert apply(Places, :nearby, [ctx.scope, @params, [fetch: fetch]]) == {:ok, []}
    assert_received {:provider, 51.0, 12.0, 0.5, 5}

    for radius <- ["0.5", "1.0", "1.5"] do
      assert {:ok, []} =
               apply(Places, :nearby, [
                 ctx.scope,
                 Map.put(@params, "radius", radius),
                 [fetch: fetch]
               ])

      assert_received {:provider, 51.0, 12.0, _, 5}
    end

    assert {:ok, []} =
             apply(Places, :nearby, [ctx.scope, %{"latitude" => "0", "longitude" => "0"}])

    assert {:ok, []} = apply(Places, :nearby, [ctx.scope, @params, [config: %{enabled: false}]])
    refute_received {:provider, _, _, _, _}
  end

  test "native nearby refuses malformed shape before provider work", ctx do
    fetch = fn _, _, _, _, _, _ ->
      send(self(), :provider_called)
      []
    end

    for params <- [
          %{},
          [],
          %{@params | "latitude" => %{}},
          %{@params | "latitude" => "NaN"},
          %{@params | "longitude" => "181"},
          Map.put(@params, "radius", "2"),
          Map.put(@params, "limit", "100")
        ] do
      assert apply(Places, :nearby, [ctx.scope, params, [fetch: fetch]]) ==
               {:error, :invalid_input}
    end

    refute_received :provider_called
  end

  test "native nearby projection excludes provider geodata and credentials", ctx do
    fetch = fn _, _, _, _, _, _ ->
      for _ <- 1..8,
          do: %{
            "name" => "Venue",
            "latitude" => 51.1,
            "longitude" => 12.1,
            "street" => "Street",
            "city" => "City",
            "country" => "Country",
            "geodata" => %{"api_key" => "synthetic-nearby-secret"},
            "api_key" => "synthetic-nearby-secret"
          }
    end

    log =
      capture_log(fn ->
        assert {:ok, results} = apply(Places, :nearby, [ctx.scope, @params, [fetch: fetch]])
        assert length(results) == 5

        assert hd(results) == %{
                 index: 0,
                 name: "Venue",
                 latitude: 51.1,
                 longitude: 12.1,
                 street: "Street",
                 city: "City",
                 country: "Country"
               }

        refute String.contains?(inspect(results), "synthetic-nearby-secret")
      end)

    refute String.contains?(log, "synthetic-nearby-secret")
  end

  test "revoked Places scope cannot start nearby provider work", ctx do
    fetch = fn _, _, _, _, _, _ ->
      send(self(), :provider_called)
      []
    end

    Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("x", 60),
      ctx.scope.user.id
    ])

    assert apply(Places, :nearby, [ctx.scope, @params, [fetch: fetch]]) ==
             {:error, :stale_session}

    refute_received :provider_called
  end
end
