defmodule Dawarich.RailsCache.SnapshotTest do
  use ExUnit.Case, async: true
  alias Dawarich.RailsCache.{Snapshot, Wire, Value}
  @fixtures Path.expand("../../fixtures/rails_cache", __DIR__)

  test "actual Rails digest snapshot becomes typed native attributes and preserves association data" do
    {:ok, entry} = Wire.decode(File.read!(Path.join(@fixtures, "codec-digest.wire")))
    attrs = Snapshot.decode(entry.value)
    assert attrs["id"] == 71
    assert attrs["travel_patterns"] == %{"weekly_pattern" => [1, 2, 3, 4, 5, 6, 7]}
    assert attrs["updated_at"] == ~N[2024-03-05 00:00:00.000000]
    reconstructed = attrs |> Snapshot.encode() |> Wire.encode() |> Wire.decode()
    assert {:ok, %{value: %Value{class: "Users::Digest"} = value}} = reconstructed
    assert Snapshot.decode(value) == attrs
  end

  test "native persisted snapshot preserves enum, UUID, microseconds and HTML safe fragment type" do
    attrs = %{
      "id" => 88,
      "user_id" => 93,
      "period_type" => 1,
      "year" => 2024,
      "sharing_uuid" => "01020304-0506-0708-090a-0b0c0d0e0f10",
      "toponyms" => [%{"country" => "Germany", "cities" => []}],
      "updated_at" => ~N[2024-03-05 12:34:56.123456]
    }

    assert attrs |> Snapshot.encode() |> Snapshot.decode() == attrs

    assert %Value{class: "ActiveSupport::SafeBuffer", tag: :user_class} =
             Snapshot.fragment("<b>safe &amp; escaped</b>")

    assert Snapshot.html(Snapshot.fragment("<b>safe &amp; escaped</b>")) ==
             "<b>safe &amp; escaped</b>"
  end

  test "actual controller fragment cache is UTF8 String, converted to safe HTML only at the fragment boundary" do
    source_fragment = "<div class=\"card\">synthetic &amp; escaped</div>"
    {:ok, entry} = source_fragment |> Wire.encode() |> Wire.decode()
    assert entry.value == source_fragment
    assert Snapshot.html(entry.value) == source_fragment
  end

  test "foreign classes and malformed cache snapshots are rejected without class construction" do
    assert_raise ArgumentError, fn ->
      Snapshot.decode(%Value{class: "User", tag: :user_marshal, value: [%{}, false]})
    end

    assert_raise ArgumentError, fn -> Snapshot.html(%Value{tag: :object, class: "Foreign"}) end
  end
end
