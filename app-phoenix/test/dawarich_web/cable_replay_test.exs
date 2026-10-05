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
        assert_recorded(c, actual, expected)
      end
    end
  end

  test "alias frame comparison permits only same-publication reordering" do
    c = A12a.case!("points_alias")
    expected = A12a.recorded(c)
    {status, protocol, type, body, steps} = expected
    {before, [first, second | after_pair]} = Enum.split(steps, 6)
    result = fn frames -> {status, protocol, type, body, frames} end

    assert_recorded(c, result.(before ++ [second, first] ++ after_pair), expected)

    assert_raise ExUnit.AssertionError, fn ->
      assert_recorded(c, result.(Enum.reverse(before) ++ [first, second] ++ after_pair), expected)
    end

    assert_raise ExUnit.AssertionError, fn ->
      assert_recorded(c, result.(before ++ [first, first] ++ after_pair), expected)
    end

    assert_raise ExUnit.AssertionError, fn ->
      assert_recorded(c, result.(before ++ [first, second] ++ Enum.reverse(after_pair)), expected)
    end

    assert_raise ExUnit.AssertionError, fn ->
      assert_recorded(
        %{"name" => "other"},
        result.(before ++ [second, first] ++ after_pair),
        expected
      )
    end
  end

  defp assert_recorded(%{"name" => "points_alias"}, actual, expected) do
    {status, protocol, type, body, steps} = actual
    {expected_status, expected_protocol, expected_type, expected_body, recorded} = expected

    assert {status, protocol, type, body} ==
             {expected_status, expected_protocol, expected_type, expected_body}

    {before, rest} = Enum.split(steps, 6)
    {pair, after_pair} = Enum.split(rest, 2)
    {recorded_before, recorded_rest} = Enum.split(recorded, 6)
    {recorded_pair, recorded_after} = Enum.split(recorded_rest, 2)
    assert before == recorded_before
    # ED-473: Rails async_invoke gives no relative order across aliased identifiers
    # for one publication. Only these two frames are a multiset; all others stay ordered.
    assert Enum.frequencies(pair) == Enum.frequencies(recorded_pair)
    assert after_pair == recorded_after
  end

  defp assert_recorded(c, actual, expected),
    do: assert({c["name"], actual} == {c["name"], expected})
end
