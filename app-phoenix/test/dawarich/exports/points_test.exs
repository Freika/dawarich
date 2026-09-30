defmodule Dawarich.Exports.PointsTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Exports.Points

  @fixture "test/fixtures/wave2/points.json" |> File.read!() |> Jason.decode!()
  @excluded ~w(created_at updated_at visit_id id import_id user_id raw_data lonlat reverse_geocoded_at country_id altitude_decimal source_id lock_version)
  @enums %{
    "battery_status" => ~w(unknown unplugged charging full connected_not_charging discharging),
    "trigger" =>
      ~w(unknown background_event circular_region_event beacon_event report_location_message_event manual_event timer_based_event settings_monitoring_event),
    "connection" => ~w(mobile wifi offline _ unknown)
  }
  @decimals ~w(altitude_decimal course course_accuracy)
  @unmapped %{"battery_status" => 9, "trigger" => 42, "connection" => 3}
  @ties ~w(0.0998 0.0999 0.1 0.1001 0.1002 0.1003)

  setup do
    root = Path.join(System.tmp_dir!(), "w2-points-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{dir: root}
  end

  defp export(format),
    do: %{
      id: 1,
      user_id: 42,
      name: "wave2 export",
      file_format: format,
      start_at: 1_774_742_400,
      end_at: 1_774_828_800,
      settings: %{}
    }

  defp user!(id) do
    rows(
      "INSERT INTO users (id, email, created_at, updated_at) VALUES ($1, $2, now(), now())",
      [id, "p#{id}@example.test"]
    )
  end

  defp insert!(table, attrs, extra_columns \\ [], extra_values \\ []) do
    {columns, values} = Enum.unzip(attrs)
    placeholders = Enum.map_join(1..length(values)//1, ", ", &"$#{&1}")

    rows(
      "INSERT INTO #{table} (#{Enum.join(columns ++ extra_columns, ", ")}, created_at, updated_at) VALUES (#{Enum.join([placeholders | extra_values], ", ")}, now(), now())",
      values
    )
  end

  defp seed_value(key, value) when is_map_key(@enums, key) and is_binary(value),
    do: Enum.find_index(@enums[key], &(&1 == value))

  defp seed_value(key, value) when key in @decimals and is_binary(value), do: Decimal.new(value)
  defp seed_value(_key, value), do: value

  defp seed_attrs(row),
    do:
      for(
        {key, value} <- Map.drop(row, ~w(created_at updated_at lonlat)),
        do: {key, seed_value(key, value)}
      )

  defp seed_fixture! do
    user!(42)

    for source <- @fixture["point_sources"], do: insert!("point_sources", seed_attrs(source))

    for point <- @fixture["points"] do
      [lon, lat] = point["lonlat"]["coordinates"]
      row = if point["id"] == 999, do: Map.merge(point, @unmapped), else: point
      lonlat = "ST_SetSRID(ST_MakePoint(#{lon * 1.0}, #{lat * 1.0}), 4326)::geography"
      insert!("points", seed_attrs(row), ["lonlat"], [lonlat])
    end
  end

  defp payload!(dir, format, time_zone, columns \\ nil) do
    path = Path.join(dir, "payload-#{format}-#{System.unique_integer([:positive])}")

    if columns,
      do: Points.write_payload!(ScratchRepo, export(format), path, time_zone, columns),
      else: Points.write_payload!(ScratchRepo, export(format), path, time_zone)

    File.read!(path)
  end

  defp canonical(payload, block, key, separator) do
    block
    |> Regex.scan(payload)
    |> Enum.map(&hd/1)
    |> Enum.chunk_by(&Regex.run(key, &1))
    |> Enum.reduce(payload, fn group, acc ->
      String.replace(
        acc,
        Enum.join(group, separator),
        group |> Enum.sort() |> Enum.join(separator)
      )
    end)
  end

  defp geojson_canonical(payload),
    do:
      canonical(
        payload,
        ~r/\{"type":"Feature",.*?"longitude":"[^"]*"\}\}/,
        ~r/"timestamp":\d+/,
        ","
      )

  defp gpx_canonical(payload),
    do: canonical(payload, ~r/      <trkpt .*?<\/trkpt>\n/s, ~r/<time>[^<]*<\/time>/, "")

  test "GeoJSON equals the Rails fixture byte for byte (Rails column order)", %{dir: dir} do
    seed_fixture!()
    by_name = Map.new(Points.columns(ScratchRepo))
    rails_order = @fixture["points_column_order"] -- @excluded
    columns = for name <- rails_order, do: {name, Map.fetch!(by_name, name)}

    for {time_zone, %{"geojson" => expected}} <- @fixture["exports"] do
      actual = payload!(dir, 0, time_zone, columns)

      assert geojson_canonical(actual) == geojson_canonical(expected), time_zone

      assert actual
             |> then(&Regex.scan(~r/"longitude":"([^"]+)"/, &1))
             |> Enum.map(&List.last/1)
             |> Enum.take(-6) == @ties
    end

    assert payload!(dir, 0, "Etc/UTC") == payload!(dir, 0, "Etc/UTC", columns)
  end

  test "GPX equals the Rails fixture byte for byte in the three time zones", %{dir: dir} do
    seed_fixture!()

    for time_zone <- ["Europe/Berlin", "Etc/UTC", "America/St_Johns"] do
      expected = @fixture["exports"][time_zone]["gpx"]
      actual = payload!(dir, 1, time_zone)

      assert gpx_canonical(actual) == gpx_canonical(expected), time_zone

      assert actual
             |> then(&Regex.scan(~r/ lon="([^"]+)"/, &1))
             |> Enum.map(&List.last/1)
             |> Enum.take(-6) == @ties
    end
  end

  test "columns/1 follows information_schema order minus the exclusions" do
    ordinal =
      rows(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'points' ORDER BY ordinal_position"
      )
      |> List.flatten()

    names = ScratchRepo |> Points.columns() |> Enum.map(&elem(&1, 0))

    assert names == ordinal -- @excluded
    assert names == @fixture["points_column_order"] -- @excluded
  end

  test "pages are 1 000 ids, each ordered by (timestamp, id)", %{dir: dir} do
    user!(42)
    :rand.seed(:exsss, {2026, 9, 28})
    timestamps = for _ <- 1..2_500, do: 1_774_748_800 + :rand.uniform(800)

    rows(
      """
      INSERT INTO points (id, user_id, timestamp, lonlat, created_at, updated_at)
      SELECT g, 42, t, ST_SetSRID(ST_MakePoint(g / 100.0, 0.00005), 4326)::geography, now(), now()
      FROM unnest($1::int[]) WITH ORDINALITY AS u(t, g)
      """,
      [timestamps]
    )

    expected =
      timestamps
      |> Enum.with_index(1)
      |> Enum.chunk_every(1_000)
      |> Enum.flat_map(fn page -> page |> Enum.sort() |> Enum.map(&elem(&1, 1)) end)

    gpx = payload!(dir, 1, "Etc/UTC")

    ids =
      ~r/ lon="([^"]+)"/
      |> Regex.scan(gpx)
      |> Enum.map(fn [_, lon] -> round(String.to_float(lon) * 100) end)

    assert ids == expected
    assert gpx |> String.split(~s(lat="5.0e-05")) |> length() == 2_501
  end

  test "the zip has one deflated entry named export.name whose bytes equal the payload", %{
    dir: dir
  } do
    seed_fixture!()
    zip = Points.write_zip!(ScratchRepo, export(1), dir, "Etc/UTC")

    assert {:ok, [{~c"wave2 export", bytes}]} = :zip.unzip(to_charlist(zip), [:memory])
    assert bytes == payload!(dir, 1, "Etc/UTC")

    assert <<0x50, 0x4B, 3, 4, _version::16, _flags::16, 8::little-16, _::binary>> =
             File.read!(zip)
  end

  test "a name over 255 bytes or with .. segments becomes the entry name, as in Rails; nothing lands outside the temp dir",
       %{dir: dir} do
    user!(42)
    work = Path.join(dir, "work")
    File.mkdir_p!(work)
    long = "trip_" <> String.duplicate("a", 300) <> "_2026-03-29.gpx"

    for name <- [long, "../../escaped"] do
      zip = Points.write_zip!(ScratchRepo, %{export(1) | name: name}, work, "Etc/UTC")

      assert <<_::binary-26, size::little-16, _::16, ^name::binary-size(size), _::binary>> =
               File.read!(zip)
    end

    assert File.ls!(dir) == ["work"]
  end

  test "a name with a leading / fails like rubyzip's EntryNameError", %{dir: dir} do
    user!(42)

    assert_raise ArgumentError, "invalid zip entry name", fn ->
      Points.write_zip!(ScratchRepo, %{export(1) | name: "/etc/passwd"}, dir, "Etc/UTC")
    end
  end
end
