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
        actual = A12a.replay(port, c)
        expected = A12a.recorded(c)
        assert {c["name"], alias_order(c, actual)} == {c["name"], alias_order(c, expected)}
      end
    end
  end

  defp alias_order(%{"name" => "points_alias"}, {status, protocol, type, body, steps}) do
    {before, rest} = Enum.split(steps, 6)
    {pair, after_pair} = Enum.split(rest, 2)
    {status, protocol, type, body, before ++ Enum.sort(pair) ++ after_pair}
  end

  defp alias_order(_case, result), do: result
end
