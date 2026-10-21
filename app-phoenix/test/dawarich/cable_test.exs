defmodule Dawarich.CableTest do
  use ExUnit.Case, async: false

  alias Dawarich.Test.A12a

  setup do
    A12a.start_bus!()
    :ok
  end

  test "broadcast_to publishes Rails' broadcasting and payload bytes for every recorded channel producer" do
    for %{"channel" => channel, "streamables" => s, "input" => input} = p <-
          A12a.corpus()["producers"],
        channel != nil do
      {:ok, _} = A12a.listen(p["broadcasting"])
      assert Dawarich.Cable.broadcast_to(channel, A12a.streamables(s), A12a.term(input)) == :ok
      assert A12a.heard() == {p["broadcasting"], p["payload"]}, p["name"]
    end
  end

  test "turbo/4 and refresh/1 build Rails' Turbo tags with escaped attributes" do
    html = ~s(<li id="x">a &amp; b</li>)

    assert Dawarich.Cable.turbo_tag("replace", ~s(t"<&>'), html) ==
             ~s(<turbo-stream action="replace" target="t&quot;&lt;&amp;&gt;&#39;"><template>) <>
               html <> "</template></turbo-stream>"

    trip = A12a.trip_id!("trip_idle")
    b = Dawarich.RailsMessages.broadcasting([{:trip, trip}])
    {:ok, _} = A12a.listen(b)
    assert Dawarich.Cable.refresh([{:trip, trip}]) == :ok
    assert A12a.heard() == {b, A12a.relay_payload("trip_path")}
  end
end
