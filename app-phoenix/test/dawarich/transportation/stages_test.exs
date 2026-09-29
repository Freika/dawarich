defmodule Dawarich.Transportation.StagesTest do
  use Dawarich.JobsCase

  alias Dawarich.Tracks.TracksFixtures

  alias Dawarich.Transportation.{
    Decoder,
    Detector,
    FeatureExtractor,
    Preprocessor,
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
      assert_close(stringify_windows(windows), data["windower"], "#{name}.windower")

      windows_input = Enum.map(data["windower"], &atomize_window/1)

      decoded = Decoder.call(windows_input, @all_modes)
      assert_close(stringify(decoded), data["decoder"], "#{name}.decoder")

      segments = Detector.call(ScratchRepo, track_map(data["track"]), enabled_modes: @all_modes)
      assert_close(stringify(segments), data["segments"], "#{name}.segments")
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
    {nil, nil}
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

    Map.put(window, :hints, Map.to_list(json_window["hints"]))
  end

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  defp stringify_windows(windows) do
    windows
    |> Enum.map(&Map.update!(&1, :hints, fn hints -> Map.new(hints) end))
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
