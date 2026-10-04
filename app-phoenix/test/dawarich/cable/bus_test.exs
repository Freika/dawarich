defmodule Dawarich.Cable.BusTest do
  use ExUnit.Case, async: false

  alias Dawarich.Cable.Bus
  alias Dawarich.Test.A12a

  setup context do
    unless context[:no_bus], do: A12a.start_bus!()
    :ok
  end

  @tag :no_bus
  test "disabled Cable starts neither transport" do
    for transport <- [:redis, :pg] do
      assert Bus.child_specs(bus: false, transport: transport) == []
    end
  end

  @tag :no_bus
  test "PG child specs keep the Bus monitor name without Cable Redix children" do
    assert [spec] = Bus.child_specs(bus: true, transport: :pg)
    assert spec.id == Bus
    assert {Dawarich.Cable.PgBus, :start_link, [opts]} = spec.start
    assert opts[:name] == Bus
    assert opts[:transport] == :pg
    assert length(Bus.child_specs(bus: true, transport: :redis)) == 2
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

  test "the prefix is resolved once, not per message" do
    rails_env = System.get_env("RAILS_ENV")
    :persistent_term.erase({Bus, :prefix})
    Application.delete_env(:dawarich, :cable_prefix)
    System.put_env("RAILS_ENV", "production")

    on_exit(fn ->
      if rails_env,
        do: System.put_env("RAILS_ENV", rails_env),
        else: System.delete_env("RAILS_ENV")

      :persistent_term.erase({Bus, :prefix})
      Application.put_env(:dawarich, :cable_prefix, "dawarich_a12a")
    end)

    assert Bus.prefix() == "dawarich_production"
    System.put_env("RAILS_ENV", "staging")
    assert Bus.prefix() == "dawarich_production"
    assert Bus.channel("points:Z2lk") == "dawarich_production:points:Z2lk"
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
