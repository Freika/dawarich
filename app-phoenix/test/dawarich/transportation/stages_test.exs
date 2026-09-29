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

      calibrated = SpeedCalibrator.call(rows)
      assert_close(stringify(calibrated), data["speed_calibrator"], "#{name}.speed_calibrator")

      preprocessed = Preprocessor.call(rows)
      assert_close(stringify(preprocessed), data["preprocessor"], "#{name}.preprocessor")

      windows = Windower.call(preprocessed)
      assert_close(stringify(windows), data["windower"], "#{name}.windower")

      decoded = Decoder.call(windows, @all_modes)
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

  test "parse_velocity follows Ruby Float()" do
    assert FeatureExtractor.parse_velocity("3.2") == 3.2
    assert FeatureExtractor.parse_velocity(" 4 ") == 4.0
    assert FeatureExtractor.parse_velocity("1_000") == 1000.0
    assert FeatureExtractor.parse_velocity("1e3") == 1000.0
    assert FeatureExtractor.parse_velocity("") == nil
    assert FeatureExtractor.parse_velocity("abc") == nil
    assert FeatureExtractor.parse_velocity(nil) == nil
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

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  defp assert_close(actual, expected, path) do
    cond do
      is_map(expected) and is_map(actual) ->
        assert Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(expected)),
               "keys mismatch at #{path}"

        Enum.each(expected, fn {k, v} -> assert_close(Map.get(actual, k), v, "#{path}.#{k}") end)

      is_list(expected) and is_list(actual) ->
        assert length(actual) == length(expected), "length mismatch at #{path}"

        actual
        |> Enum.zip(expected)
        |> Enum.with_index()
        |> Enum.each(fn {{a, e}, i} -> assert_close(a, e, "#{path}[#{i}]") end)

      is_float(expected) and is_number(actual) ->
        assert_float_close(actual * 1.0, expected, path)

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
