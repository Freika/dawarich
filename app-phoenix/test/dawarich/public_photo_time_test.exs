defmodule Dawarich.Sharing.PublicPhotoTimeTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Repo, Sharing.PublicSnapshot}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  for {zone, expected} <- [
        {"UTC", "2026-05-10T00:30:00Z"},
        {"Europe/Berlin", "2026-05-09T22:30:00Z"}
      ] do
    @zone zone
    @expected expected
    test "native photo DTO normalizes offset-free midnight in #{@zone}" do
      raw = {:object, [{"taken_at", "2026-05-10T00:30:00"}, {"id", "synthetic-photo"}]}
      [photo] = PublicSnapshot.photos([raw], @zone)
      assert photo["taken_at"] == @expected
      assert photo["day_key"] == "2026-05-10"
    end
  end

  test "native photo DTO retains an offset timestamp instant and computes the owner's day" do
    raw = {:object, [{"taken_at", "2026-05-09T22:30:00Z"}]}
    [photo] = PublicSnapshot.photos([raw], "Europe/Berlin")
    assert photo["taken_at"] == "2026-05-09T22:30:00Z"
    assert photo["day_key"] == "2026-05-10"
  end

  test "native photo DTO keeps undated photos without assigning them to an arbitrary day" do
    for value <- [nil, "", "2026-99-10T00:30:00", String.duplicate("x", 129)] do
      [photo] =
        PublicSnapshot.photos([{:object, [{"taken_at", value}, {"id", "undated"}]}], "UTC")

      assert photo["id"] == "undated"
      assert photo["day_key"] == nil
      assert photo["taken_at"] == value
    end
  end

  test "native photo DTO computes owner days for all dated photos in one query" do
    raw =
      for(day <- 1..5, do: {:object, [{"taken_at", "2026-05-0#{day}T00:30:00"}]}) ++
        [{:object, [{"taken_at", nil}]}]

    handler = "public-photo-days-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ ->
        if self() == parent, do: send(parent, {:photo_day_query, metadata.query})
      end,
      nil
    )

    photos =
      try do
        PublicSnapshot.photos(raw, "Europe/Berlin")
      after
        :telemetry.detach(handler)
      end

    assert Enum.map(photos, & &1["day_key"]) ==
             ["2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05", nil]

    assert_received {:photo_day_query, _}
    refute_received {:photo_day_query, _}
  end
end
