defmodule Dawarich.MapMatching.ProcessorTest do
  use ExUnit.Case, async: true
  alias Dawarich.MapMatching.{Input, Processor}

  @geometry %{"type" => "LineString", "coordinates" => [[13.4, 52.5], [13.405, 52.505]]}
  @response %{
    geometry: @geometry,
    stats: %{"matched" => 2},
    provider: %{version: "0.6.0", revision: "abc"}
  }

  defp input(modes) do
    points =
      for i <- 0..length(modes),
          do: %{
            id: i + 1,
            timestamp: 100 + i * 10,
            lon: 13.4 + i / 100,
            lat: 52.5 + i / 100,
            accuracy: 5.0
          }

    segments =
      modes
      |> Enum.with_index()
      |> Enum.map(fn {mode, i} ->
        %{
          id: i + 1,
          transportation_mode: mode,
          start_index: i,
          end_index: i + 1,
          start_at: nil,
          end_at: nil
        }
      end)

    Input.new(points, segments)
  end

  defp success(_url, %{shape: [first, second], costing: mode})
       when mode in ["pedestrian", "bicycle"] do
    true = first.time < second.time
    true = first.accuracy == 5.0
    {:ok, @response}
  end

  test "all portions accepted → matched" do
    assert {:ok, result} = Processor.call(input(["walking", "cycling"]), &success/2)
    assert result.status == :matched

    assert result.path.coordinates == [
             [{13.4, 52.5}, {13.405, 52.505}],
             [{13.4, 52.5}, {13.405, 52.505}]
           ]

    assert Enum.map(result.data.segments, & &1.result) == ["accepted", "accepted"]
    assert result.data.provider == %{name: "atlas", version: "0.6.0", revision: "abc"}
  end

  test "accepted + fallback → partial" do
    response = %{
      @response
      | geometry: %{
          "type" => "MultiLineString",
          "coordinates" => [@geometry["coordinates"], [[14, 53], [15, 54]]]
        }
    }

    assert {:ok, result} =
             Processor.call(input(["walking", "train", "cycling"]), fn _, _ -> {:ok, response} end)

    assert result.status == :partial

    assert result.path.coordinates == [
             [{13.4, 52.5}, {13.405, 52.505}],
             [{14, 53}, {15, 54}],
             [{13.41, 52.51}, {13.42, 52.52}],
             [{13.4, 52.5}, {13.405, 52.505}],
             [{14, 53}, {15, 54}]
           ]

    assert Enum.map(result.data.segments, & &1.result) == ["accepted", "unsupported", "accepted"]
  end

  test "none accepted → rejected" do
    assert {:ok, result} =
             Processor.call(input(["walking"]), fn _, _ ->
               {:ok, %{@response | stats: %{"matched" => 0}}}
             end)

    assert result.status == :rejected
    assert result.path == nil
    assert hd(result.data.segments).reasons == ["no_matched_points"]
  end

  test "no eligible → skipped" do
    original = input(["train"])

    assert {:ok, result} =
             Processor.call(original, fn _, _ -> flunk("unsupported input sent to Atlas") end)

    assert result == Processor.skipped(original)
    assert result.status == :skipped
    assert result.path == nil
    assert result.data.provider == %{name: "atlas"}
    assert hd(result.data.segments).result == "unsupported"
  end

  test "422 portion keeps original geometry" do
    for status <- [400, 422] do
      client = fn _, %{costing: costing} ->
        if costing == "pedestrian",
          do: {:ok, @response},
          else: {:error, %{code: "invalid_input", status: status, transient?: false}}
      end

      assert {:ok, result} = Processor.call(input(["walking", "cycling"]), client)
      assert result.status == :partial

      assert result.path.coordinates == [
               [{13.4, 52.5}, {13.405, 52.505}],
               [{13.41, 52.51}, {13.42, 52.52}]
             ]

      assert List.last(result.data.segments).reasons == ["invalid_input"]
    end
  end

  test "too_many_points rejected" do
    small = input(["walking"])
    [portion] = small.portions

    oversized = %{
      small
      | portions: [%{portion | points: List.duplicate(hd(portion.points), 10_001)}]
    }

    assert {:ok, result} =
             Processor.call(oversized, fn _, _ -> flunk("oversized input sent to Atlas") end)

    assert result.status == :rejected
    assert result.path == nil
    assert hd(result.data.segments).reasons == ["too_many_points"]

    boundary = %{
      small
      | portions: [%{portion | points: List.duplicate(hd(portion.points), 10_000)}]
    }

    assert {:ok, %{status: :matched}} = Processor.call(boundary, fn _, _ -> {:ok, @response} end)
  end

  test "transient error propagates" do
    for {code, status, retry_after} <- [
          {"rate_limited", 429, 7},
          {"unavailable", 503, nil},
          {"timeout", nil, nil},
          {"provider_invalid", 200, nil}
        ] do
      error = %{code: code, status: status, retry_after: retry_after, transient?: true}
      assert Processor.call(input(["walking"]), fn _, _ -> {:error, error} end) == {:error, error}
    end
  end

  test "data has no PII" do
    raw = "trace 13.418765 52.512345 time=1790900000"

    response = %{
      @response
      | stats: %{
          "matched" => 2,
          "unmatched" => 0,
          "mean_distance_from_trace_point" => 4.2,
          "raw_score" => raw,
          "shape" => raw
        },
        provider: %{version: "0.6.0", revision: "abc", body: raw}
    }

    client = fn _, %{costing: costing} ->
      if costing == "pedestrian",
        do: {:ok, response},
        else:
          {:error,
           %{code: "invalid_input", status: 422, transient?: false, message: raw, body: raw}}
    end

    assert {:ok, result} = Processor.call(input(["walking", "cycling"]), client)
    data = result.data
    assert data.schema_version == 1
    assert data.policy_version == 1
    assert data.error == nil
    assert hd(data.segments).stats == %{matched: 2, unmatched: 0, mean_distance: 4.2}
    assert List.last(data.segments).reasons == ["invalid_input"]
    encoded = Jason.encode!(data)

    for forbidden <- [
          raw,
          "coordinates",
          "timestamp",
          "accuracy",
          "body",
          "shape",
          "start_index",
          "segment:1"
        ],
        do: refute(encoded =~ forbidden)
  end

  test "JSON provider metadata retains version and omits missing revision" do
    response = %{
      @response
      | provider: %{"version" => "0.6.0", "revision" => nil, "body" => "discard"}
    }

    assert {:ok, result} = Processor.call(input(["walking"]), fn _, _ -> {:ok, response} end)
    assert result.data.provider == %{name: "atlas", version: "0.6.0"}
  end
end
