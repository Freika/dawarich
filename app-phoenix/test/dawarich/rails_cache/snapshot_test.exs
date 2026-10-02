defmodule Dawarich.RailsCache.SnapshotTest do
  use ExUnit.Case, async: true
  alias Dawarich.RailsCache.{Snapshot, Wire, Value}
  @fixtures Path.expand("../../fixtures/rails_cache", __DIR__)

  test "actual Rails digest snapshot becomes typed native attributes" do
    {:ok, entry} = Wire.decode(File.read!(Path.join(@fixtures, "codec-digest.wire")))
    attrs = Snapshot.decode(entry.value)
    assert attrs["id"] == 71
    assert attrs["travel_patterns"] == %{"weekly_pattern" => [1, 2, 3, 4, 5, 6, 7]}
    assert attrs["updated_at"] == ~N[2024-03-05 00:00:00.000000]
  end

  test "actual controller fragment cache is a UTF-8 String; a SafeBuffer is read as its HTML" do
    source_fragment = "<div class=\"card\">synthetic &amp; escaped</div>"
    {:ok, entry} = source_fragment |> Wire.encode() |> Wire.decode()
    assert Snapshot.html(entry.value) == source_fragment

    safe = %Value{tag: :user_class, class: "ActiveSupport::SafeBuffer", value: source_fragment}
    assert Snapshot.html(safe) == source_fragment
  end

  test "foreign classes and malformed cache snapshots are rejected without class construction" do
    assert_raise ArgumentError, fn ->
      Snapshot.decode(%Value{class: "User", tag: :user_marshal, value: [%{}, false]})
    end

    assert_raise ArgumentError, fn -> Snapshot.html(%Value{tag: :object, class: "Foreign"}) end
  end
end
