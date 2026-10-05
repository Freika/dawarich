defmodule Dawarich.Points.RecordsDeviceTagsTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Points.RecordsDeviceTags

  @source Path.expand("../../fixtures/a12d1b3/Records.json", __DIR__)
  @now ~U[2026-10-03 12:00:00Z]

  test "matches original-file timestamp clamps and nested-field exclusion" do
    values = [
      "1960-01-01T00:00:00Z",
      "2200-01-01T00:00:00Z",
      "2025-03-15T12:00:00Z",
      "1742040000000",
      -1,
      "bad",
      "",
      "-1001",
      "2025-03-15T12:00:00.999Z"
    ]

    for {zone, first, last} <- [
          {"UTC", 0, 4_102_444_800},
          {"Europe/Berlin", -3600, 4_102_441_200},
          {"Asia/Tokyo", -32400, 4_102_412_400},
          {"America/New_York", 18000, 4_102_462_800}
        ] do
      context = %{repo: ScratchRepo, zone: zone, now: @now}

      assert Enum.map(values, &RecordsDeviceTags.timestamp(&1, context)) ==
               [
                 first,
                 last,
                 1_742_040_000,
                 1_742_040_000,
                 max(-1, first),
                 max(0, first),
                 max(0, first),
                 1_790_812_800,
                 1_742_040_000
               ]
    end

    {settled, contested} = RecordsDeviceTags.read(@source, context())
    assert Map.keys(settled) == [1_742_040_600]
    assert Enum.all?(Map.keys(contested), fn {at, _, _} -> at == 1_742_040_000 end)
    path = Path.join(System.tmp_dir!(), "records-tags-#{Ecto.UUID.generate()}.json")
    on_exit(fn -> File.rm(path) end)

    File.write!(
      path,
      Jason.encode!(%{
        "locations" => [
          %{"timestamp" => nil, "timestampMs" => "1742040000000", "deviceTag" => 0},
          %{"timestamp" => "2025-03-15T12:10:00Z", "deviceTag" => ""},
          %{"timestamp" => "2025-03-15T12:20:00Z", "deviceTag" => nil},
          %{"timestamp" => "2025-03-15T12:30:00Z", "deviceTag" => false},
          %{"activity" => [%{"timestamp" => "2025-03-15T12:40:00Z", "deviceTag" => 9}]}
        ]
      })
    )

    assert RecordsDeviceTags.read(path, context()) ==
             {%{1_742_040_000 => "0", 1_742_040_600 => ""}, %{}}
  end

  test "resolves contested seconds by E7 position and leaves equal-position collisions" do
    assert RecordsDeviceTags.read(@source, context()) == {
             %{1_742_040_600 => "55"},
             %{
               {1_742_040_000, 510_000_000, 120_000_000} => "11",
               {1_742_040_000, 510_001_000, 120_001_000} => "22"
             }
           }
  end

  defp context, do: %{repo: ScratchRepo, zone: "Europe/Berlin", now: @now}
end
