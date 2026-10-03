defmodule DawarichWeb.CableReplayTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Test.A12a

  @moduletag timeout: 120_000
  @options %{
    "origin_localhost_development" => [env: %{"RAILS_ENV" => "development"}],
    "family_cloud_lapsed" => [self_hosted: false]
  }

  setup do
    A12a.seed!()
    A12a.start_bus!()
    ports = for {name, opts} <- @options, into: %{}, do: {name, A12a.serve_cable!(opts)}
    {:ok, port: A12a.serve_cable!(), ports: ports}
  end

  for section <- ~w(handshake connect subscribe commands messages) do
    test "replays every recorded Rails #{section} case", %{port: port, ports: ports} do
      for c <- A12a.cases(unquote(section)), c["name"] not in A12a.ed_cases() do
        port = Map.get(ports, c["name"], port)
        assert {c["name"], A12a.replay(port, c)} == {c["name"], A12a.recorded(c)}
      end
    end
  end
end
