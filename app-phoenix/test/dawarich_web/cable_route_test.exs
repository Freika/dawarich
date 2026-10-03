defmodule DawarichWeb.CableRouteTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP, only: [ws_request: 4, read_response_head: 1]

  alias Dawarich.Test.{A12a, FakeCable}

  setup do
    previous =
      Map.new([:rails_upstream, :rails_routes], &{&1, Application.fetch_env(:dawarich, &1)})

    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, FakeCable.start(self())})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, configured} -> Application.put_env(:dawarich, key, configured)
          :error -> Application.delete_env(:dawarich, key)
        end
      end
    end)

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    {:ok, port: port}
  end

  defp upgrade!(port) do
    host = "127.0.0.1:#{port}"
    socket = ws_request(port, "/cable", [{"Origin", "http://" <> host}], host)
    {status, headers, _rest} = read_response_head(socket)
    {status, headers}
  end

  defp with_system_env(name, value, fun) do
    previous = System.get_env(name)
    System.put_env(name, value)

    try do
      fun.()
    after
      if previous, do: System.put_env(name, previous), else: System.delete_env(name)
    end
  end

  test "an owned /cable upgrade is answered by Phoenix; DAWARICH_RAILS_ROUTES=cable and Cloud hand it to Puma",
       %{port: port} do
    assert {101, _} = upgrade!(port)
    refute_receive {:cable_request, "/cable", _, _}, 200

    Application.put_env(:dawarich, :rails_routes, ["cable"])
    assert {101, _} = upgrade!(port)
    assert_receive {:cable_request, "/cable", _, _}
    Application.put_env(:dawarich, :rails_routes, [])

    with_system_env("SELF_HOSTED", "false", fn ->
      assert {101, _} = upgrade!(port)
      assert_receive {:cable_request, "/cable", _, _}
    end)

    with_system_env("DAWARICH_RAILS_SLICES", "cable", fn ->
      assert {101, _} = upgrade!(port)
      assert_receive {:cable_request, "/cable", _, _}
    end)
  end

  test "the Bus is a child of the application" do
    previous = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, bus: true, url: A12a.test_redis_url(), database: 2)
    on_exit(fn -> Application.put_env(:dawarich, :cable, previous) end)

    children = Dawarich.Application.children(Dawarich.Front.plan(nil, %{}))
    assert Enum.any?(children, &match?(%{id: Dawarich.Cable.Bus}, &1))
  end
end
