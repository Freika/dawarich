defmodule Dawarich.Cable.BusTest do
  use ExUnit.Case, async: false

  alias Dawarich.Cable.Bus
  alias Dawarich.Test.A12a

  setup do
    A12a.start_bus!()
    :ok
  end

  test "the prefix follows RAILS_ENV like config/cable.yml" do
    Application.delete_env(:dawarich, :cable_prefix)
    on_exit(fn -> Application.put_env(:dawarich, :cable_prefix, "dawarich_a12a") end)
    assert Bus.prefix(%{"RAILS_ENV" => "production"}) == "dawarich_production"
    assert Bus.prefix(%{"RAILS_ENV" => "staging"}) == "dawarich_staging"
    assert Bus.prefix(%{"RACK_ENV" => "development"}) == "dawarich_development"
    assert Bus.prefix(%{"RAILS_ENV" => ""}) == "dawarich_development"
    assert Bus.prefix(%{}) == "dawarich_development"
    assert Bus.prefix(%{"RAILS_ENV" => "test"}) == nil
  end

  test "a subscriber is acknowledged, then receives Rails' channel with the prefix stripped" do
    {:ok, _ref} = Bus.subscribe("points:Z2lk")
    assert_receive message, 2_000
    assert Bus.event(message) == {:subscribed, "points:Z2lk"}
    {:ok, 1} = Bus.publish("points:Z2lk", ~s(["x"]))
    assert_receive message, 2_000
    assert Bus.event(message) == {:message, "points:Z2lk", ~s(["x"])}
    {:ok, 0} = Bus.publish("tracks:Z2lk", "1")
  end
end
