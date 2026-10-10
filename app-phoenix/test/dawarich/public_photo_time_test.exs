defmodule Dawarich.Sharing.PublicPhotoTimeTest do
  use ExUnit.Case, async: true
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
end
