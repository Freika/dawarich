defmodule Dawarich.TrackSegments.DisplayLegsTest do
  use ExUnit.Case, async: true
  alias Dawarich.TrackSegments.DisplayLegs

  defp segment(id, start, finish, attrs \\ %{}) do
    Map.merge(
      %{
        id: id,
        start_at: DateTime.add(~U[2026-03-01 10:00:00Z], start, :second),
        end_at: DateTime.add(~U[2026-03-01 10:00:00Z], finish, :second),
        duration: finish - start,
        distance: 100,
        transportation_mode: "walking",
        confidence_score: 0.9,
        corrected_at: nil
      },
      attrs
    )
  end

  test "legacy and all stationary segments use raw rows" do
    assert nil == DisplayLegs.call([])
    assert nil == DisplayLegs.call([segment(1, 0, 600), segment(2, 600, 1200, %{start_at: nil})])
    assert nil == DisplayLegs.call([segment(1, 0, 600, %{transportation_mode: "stationary"})])
  end

  test "a real leg and uncertain leg carry their single segment id" do
    %{items: items} =
      DisplayLegs.call([
        segment(1, 0, 600),
        segment(2, 600, 1200, %{transportation_mode: "unknown", distance: nil, duration: nil})
      ])

    assert [
             %{kind: :leg, mode: "walking", segment_id: 1},
             %{kind: :uncertain, mode: nil, segment_id: 2}
           ] = items

    assert Enum.at(items, 1).distance == 0
  end

  test "a transfer and inferred stop carry no editable segment id" do
    %{items: items} =
      DisplayLegs.call([segment(1, 0, 100), segment(2, 100, 200), segment(3, 500, 1100)])

    assert [
             %{kind: :transfer, segment_id: nil, segment_count: 2, duration: 200},
             %{kind: :stop, duration: 300, segment_id: nil},
             %{segment_id: 3}
           ] = items
  end

  test "confidence below point six is uncertain unless corrected" do
    rows = [
      segment(1, 0, 600, %{confidence_score: 0.59}),
      segment(2, 600, 1200, %{confidence_score: 0.6}),
      segment(3, 1200, 1800, %{confidence_score: 0.1, corrected_at: ~N[2026-03-01 10:00:00]})
    ]

    assert [:uncertain, :leg, :leg] == Enum.map(DisplayLegs.call(rows).items, & &1.kind)
  end

  test "consecutive micro segments merge but an isolated short leg remains" do
    rows = [segment(1, 0, 100), segment(2, 101, 200), segment(3, 200, 800), segment(4, 800, 900)]

    assert [
             %{kind: :transfer, distance: 200, duration: 200},
             %{kind: :leg},
             %{kind: :leg, segment_id: 4}
           ] = DisplayLegs.call(rows).items
  end

  test "stop gap is inclusive at two hundred forty seconds" do
    assert [:leg, :stop, :leg] ==
             Enum.map(
               DisplayLegs.call([segment(1, 0, 600), segment(2, 840, 1440)]).items,
               & &1.kind
             )

    assert [:leg, :leg] ==
             Enum.map(
               DisplayLegs.call([segment(1, 0, 600), segment(2, 839, 1439)]).items,
               & &1.kind
             )
  end

  test "corrected short legs retain their mode and never merge" do
    rows = [
      segment(1, 0, 100, %{
        corrected_at: ~N[2026-03-01 10:00:00],
        transportation_mode: "driving",
        confidence_score: 0.1
      }),
      segment(2, 100, 200)
    ]

    assert [%{kind: :leg, mode: "driving", segment_id: 1}, %{kind: :leg, segment_id: 2}] =
             DisplayLegs.call(rows).items
  end

  test "ribbon includes gaps tail and Ruby rounded percentages" do
    rows = [
      segment(3, 800, 900, %{transportation_mode: "stationary"}),
      segment(2, 200, 800),
      segment(1, 0, 100, %{transportation_mode: "stationary"})
    ]

    assert [
             %{kind: :gap, percent: 22.2},
             %{kind: :mode, mode: "walking", percent: 66.7},
             %{kind: :gap, percent: 11.1}
           ] = DisplayLegs.call(rows).spans
  end

  test "zero total duration gives an empty ribbon" do
    assert %{spans: []} = DisplayLegs.call([segment(1, 0, 0)])
  end
end
