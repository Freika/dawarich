defmodule Dawarich.Transportation.StagesTest do
  use Dawarich.JobsCase

  alias Dawarich.Tracks.TracksFixtures

  alias Dawarich.Transportation.{
    Decoder,
    Detector,
    FeatureExtractor,
    Preprocessor,
    SegmentAssembler,
    SpeedCalibrator,
    Windower
  }

  @all_modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)

  setup do
    ScratchRepo.query!(
      "TRUNCATE tracks, points, track_segments, imports RESTART IDENTITY CASCADE",
      [],
      log: false
    )

    :ok
  end

  test "each stage reproduces Rails on every fixture track" do
    %{expected: expected} = TracksFixtures.load!(ScratchRepo, "transport_stages")
    ordered = ordered_windows()

    Enum.each(expected, fn {name, data} ->
      rows = FeatureExtractor.rows(ScratchRepo, data["track"]["id"])
      assert_close(stringify(rows), data["feature_extractor"], "#{name}.feature_extractor")

      fx_rows = Enum.map(data["feature_extractor"], &atomize_row/1)

      calibrated = SpeedCalibrator.call(fx_rows)
      assert_close(stringify(calibrated), data["speed_calibrator"], "#{name}.speed_calibrator")

      preprocessed = Preprocessor.call(fx_rows)
      assert_close(stringify(preprocessed), data["preprocessor"], "#{name}.preprocessor")

      preprocessed_rows = Enum.map(data["preprocessor"], &atomize_preprocessed_row/1)

      windows = Windower.call(preprocessed_rows)
      expected_windows = with_ordered_hints(data["windower"], ordered[name])
      assert_close(stringify_windows(windows), expected_windows, "#{name}.windower")

      windows_input = Enum.map(expected_windows, &atomize_window/1)

      decoded = Decoder.call(windows_input, @all_modes)
      assert_close(stringify(decoded), data["decoder"], "#{name}.decoder")

      segments = Detector.call(ScratchRepo, track_map(data["track"]), enabled_modes: @all_modes)
      assert_close(stringify(segments), data["segments"], "#{name}.segments")
    end)
  end

  test "SegmentAssembler reproduces Rails from the fixture's own stage inputs" do
    %{"expected" => expected} = TracksFixtures.read!("transport_stages")
    ordered = ordered_windows()

    assembled_tracks =
      Enum.reject(expected, fn {_name, data} ->
        match?([%{"source" => "default"}], data["segments"])
      end)

    assert length(assembled_tracks) == map_size(expected) - 1

    Enum.each(assembled_tracks, fn {name, data} ->
      rows = Enum.map(data["preprocessor"], &atomize_preprocessed_row/1)

      windows =
        data["windower"] |> with_ordered_hints(ordered[name]) |> Enum.map(&atomize_window/1)

      decoded = Enum.map(data["decoder"], &%{mode: &1["mode"], posterior: &1["posterior"]})

      assembled = SegmentAssembler.call(rows, windows, decoded, [])
      assert_close(stringify(assembled), data["segments"], "#{name}.segment_assembler")
    end)
  end

  test "FeatureExtractor SQL returns Rails' rows" do
    %{expected: expected} = TracksFixtures.load!(ScratchRepo, "transport_stages")

    Enum.each(expected, fn {name, data} ->
      rows = FeatureExtractor.rows(ScratchRepo, data["track"]["id"])
      assert_close(stringify(rows), data["feature_extractor"], "#{name}.feature_extractor")
    end)
  end

  @velocity_cases [
    {"3.2", 3.2},
    {" 4 ", 4.0},
    {"1_000", 1000.0},
    {"1e3", 1000.0},
    {".5", 0.5},
    {"5.", 5.0},
    {"+.5", 0.5},
    {"0x1A", 26.0},
    {"-0x1A", -26.0},
    {"_1", nil},
    {"1__0", nil},
    {"1_", nil},
    {"", nil},
    {"abc", nil},
    {nil, nil},
    {"0x1p3", 8.0},
    {"0x1.8", 1.5},
    {"0x1.8p1", 3.0},
    {"0xFFp2", 1020.0},
    {"-0x.8p1", -1.0},
    {"0x0 ", nil},
    {"0x1p-1075", 0.0},
    {"\u00A05", nil},
    {"5\u2003", nil},
    {"\u00855", nil},
    {"\t5\v", 5.0},
    {"\f5\r", 5.0},
    {"1e400", nil},
    {"-1e400", nil},
    {"0x1p1024", nil},
    {"0x" <> String.duplicate("F", 260), nil}
  ]

  test "parse_velocity follows Ruby 3.4's Float()" do
    for {input, expected} <- @velocity_cases do
      assert FeatureExtractor.parse_velocity(input) == expected, "input: #{inspect(input)}"
    end
  end

  test "parse_motion_data returns binaries unchanged (Postgrex already decoded jsonb once)" do
    assert FeatureExtractor.parse_motion_data("IN_VEHICLE") == "IN_VEHICLE"

    assert FeatureExtractor.parse_motion_data(~s({"activityType":"IN_VEHICLE"})) ==
             ~s({"activityType":"IN_VEHICLE"})

    assert FeatureExtractor.parse_motion_data(%{"activityType" => "IN_VEHICLE"}) == %{
             "activityType" => "IN_VEHICLE"
           }

    assert FeatureExtractor.parse_motion_data(nil) == %{}
    assert FeatureExtractor.parse_motion_data("") == %{}
  end

  defp track_map(track) do
    %{
      id: track["id"],
      start_at: track["start_at"],
      end_at: track["end_at"],
      distance: track["distance"],
      duration: track["duration"],
      avg_speed: track["avg_speed"]
    }
  end

  @row_keys ~w(point_id ts accuracy velocity motion_data lon lat dt dist_m bearing_deg)a
  @preprocessed_extra_keys ~w(speed_mps speed_valid bearing_delta_deg)a
  @window_keys ~w(start_ts end_ts mean_dt speed_p50 speed_p85 speed_p95 heading_change_rate
                  motion_variance stop_fraction sparse point_ids gap_before)a

  defp atomize_row(json_row) do
    Map.new(@row_keys, fn key -> {key, Map.fetch!(json_row, Atom.to_string(key))} end)
  end

  defp atomize_preprocessed_row(json_row) do
    row = atomize_row(json_row)

    Enum.reduce(@preprocessed_extra_keys, row, fn key, acc ->
      Map.put(acc, key, Map.fetch!(json_row, Atom.to_string(key)))
    end)
  end

  defp atomize_window(json_window) do
    window =
      Map.new(@window_keys, fn key -> {key, Map.fetch!(json_window, Atom.to_string(key))} end)

    Map.put(window, :hints, Enum.map(json_window["hints"], fn [mode, value] -> {mode, value} end))
  end

  defp ordered_windows do
    ordered = TracksFixtures.read!("transport_stages", objects: :ordered_objects)

    Map.new(ordered["expected"].values, fn {name, data} ->
      {name, Enum.map(data["windower"], &hint_pairs(&1["hints"]))}
    end)
  end

  defp hint_pairs(%Jason.OrderedObject{values: values}),
    do: Enum.map(values, fn {mode, value} -> [mode, value] end)

  defp with_ordered_hints(windows, ordered_hints) do
    Enum.zip_with(windows, ordered_hints, &Map.put(&1, "hints", &2))
  end

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  defp stringify_windows(windows) do
    windows
    |> Enum.map(fn window ->
      Map.update!(window, :hints, &Enum.map(&1, fn h -> Tuple.to_list(h) end))
    end)
    |> stringify()
  end

  @rounded_fields ~w(distance avg_speed max_speed confidence_score posterior)

  defp assert_close(actual, expected, path, key \\ nil) do
    cond do
      is_map(expected) and is_map(actual) ->
        assert Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(expected)),
               "keys mismatch at #{path}"

        Enum.each(expected, fn {k, v} ->
          assert_close(Map.get(actual, k), v, "#{path}.#{k}", k)
        end)

      is_list(expected) and is_list(actual) ->
        assert length(actual) == length(expected), "length mismatch at #{path}"

        actual
        |> Enum.zip(expected)
        |> Enum.with_index()
        |> Enum.each(fn {{a, e}, i} -> assert_close(a, e, "#{path}[#{i}]", key) end)

      is_float(expected) ->
        assert is_float(actual),
               "type mismatch at #{path}: expected Float #{inspect(expected)}, got #{inspect(actual)}"

        if key in @rounded_fields do
          assert actual == expected,
                 "rounded-float mismatch at #{path}: #{inspect(actual)} != #{inspect(expected)}"
        else
          assert_float_close(actual, expected, path)
        end

      is_integer(expected) ->
        assert is_integer(actual),
               "type mismatch at #{path}: expected Integer #{inspect(expected)}, got #{inspect(actual)}"

        assert actual == expected,
               "mismatch at #{path}: #{inspect(actual)} != #{inspect(expected)}"

      true ->
        assert actual == expected,
               "mismatch at #{path}: #{inspect(actual)} != #{inspect(expected)}"
    end
  end

  defp assert_float_close(actual, expected, path) do
    diff = abs(actual - expected)
    tolerance = max(abs(expected) * 1.0e-12, 1.0e-12)

    assert diff <= tolerance,
           "float mismatch at #{path}: #{inspect(actual)} != #{inspect(expected)} (diff=#{diff})"
  end
end
