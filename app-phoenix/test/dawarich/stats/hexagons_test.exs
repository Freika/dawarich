defmodule Dawarich.Stats.HexagonsTest do
  use Dawarich.JobsCase

  alias Dawarich.StatsFixtures, as: F
  alias Dawarich.Stats.{Accounts, Hexagons}

  @jan1 1_704_067_200

  setup do
    F.reset!()
    F.user!(61, %{"timezone" => "Etc/UTC"})
    :ok
  end

  test "a month without points has no cells, whatever other accounts recorded" do
    F.user!(62, %{"timezone" => "Etc/UTC"})
    F.point!(6201, 62, @jan1 + 43_200)
    assert Hexagons.calculate(ScratchRepo, Accounts.find(ScratchRepo, 61), 2024, 1) == []
  end

  test "counts points per cell with first and last timestamps, cells in first-seen id order, across batches" do
    F.point!(6101, 61, @jan1 + 43_200, %{"lonlat" => "SRID=4326;POINT(12.3731 51.3397)"})
    F.point!(6102, 61, @jan1 + 39_600, %{"lonlat" => "SRID=4326;POINT(11.9697 51.4825)"})
    F.point!(6103, 61, @jan1 + 46_800, %{"lonlat" => "SRID=4326;POINT(12.3741 51.3402)"})

    F.point!(6104, 61, @jan1 + 3_600, %{
      "lonlat" => "SRID=4326;POINT(12.3732 51.3398)",
      "anomaly" => true
    })

    F.point!(6105, 61, @jan1 - 3_600, %{"lonlat" => "SRID=4326;POINT(12.3732 51.3398)"})
    user = Accounts.find(ScratchRepo, 61)

    expected = [
      ["881f1a8cb5fffff", 2, @jan1 + 43_200, @jan1 + 46_800],
      ["881f1a98c9fffff", 1, @jan1 + 39_600, @jan1 + 39_600]
    ]

    assert Hexagons.calculate(ScratchRepo, user, 2024, 1) == expected
    assert Hexagons.calculate(ScratchRepo, user, 2024, 1, batch: 1) == expected

    assert [["861f1a8cfffffff", 2, _, _], ["861f1a9afffffff", 1, _, _]] =
             Hexagons.calculate(ScratchRepo, user, 2024, 1, resolution: 6)
  end
end
