defmodule DawarichWeb.NativeMapConfigStabilityTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  test "map readiness and unrelated events do not republish unchanged configuration" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-stability-#{id}@example.invalid",
      settings: %{"timezone" => "UTC", "enabled_map_layers" => ["Points", "Tracks"]}
    })

    {:ok, view, _} =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> get("/map/v2")
      |> live()

    assert_push_event(view, "map:config", %{})
    drain_configs()
    render_hook(view, "map:ready", %{"revision" => 1})
    refute_receive {_, {:push_event, "map:config", _}}
    render_hook(view, "map:failed", %{"code" => "synthetic"})
    refute_receive {_, {:push_event, "map:config", _}}
    assert has_element?(view, "[data-testid=map-button-timeline]")
  end

  test "map lifecycle reports do not reload the navbar" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-lifecycle-#{id}@example.invalid",
      settings: %{"timezone" => "UTC", "enabled_map_layers" => ["Points", "Tracks"]}
    })

    {:ok, view, _} =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> get("/map/v2")
      |> live()

    test = self()
    key = {__MODULE__, make_ref()}
    pid = view.pid

    :telemetry.attach(
      key,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ -> if self() == pid, do: send(test, {key, metadata.query}) end,
      nil
    )

    try do
      render_hook(view, "map:ready", %{"revision" => 1})
      render_hook(view, "map:failed", %{"code" => "synthetic"})
      queries = collect(key, [])
      assert length(queries) <= 2
      assert Enum.all?(queries, &(&1 =~ ~s(FROM "public"."users" AS u0)))
    after
      :telemetry.detach(key)
    end
  end

  defp collect(key, acc) do
    receive do
      {^key, query} -> collect(key, [query | acc])
    after
      50 -> acc
    end
  end

  defp drain_configs do
    receive do
      {_, {:push_event, "map:config", _}} -> drain_configs()
    after
      0 -> :ok
    end
  end
end
