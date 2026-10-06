defmodule Dawarich.MapMatching.Input do
  alias Dawarich.MapMatching.ModeMapper
  alias Dawarich.Transportation.Segments

  defmodule Point do
    defstruct [:id, :timestamp, :lon, :lat, :accuracy]

    def atlas_shape(point) do
      shape = %{lat: point.lat, lon: point.lon, time: point.timestamp}
      if is_nil(point.accuracy), do: shape, else: Map.put(shape, :accuracy, point.accuracy)
    end
  end

  defmodule Portion do
    defstruct [:key, :transportation_mode, :atlas_mode, :start_index, :end_index, points: []]
  end

  defstruct points: [], portions: [], segment_fingerprint: []

  def load(repo, track_id) do
    points =
      repo.query!(
        """
        SELECT id, timestamp, ST_X(lonlat::geometry), ST_Y(lonlat::geometry), accuracy
        FROM points WHERE track_id = $1 AND anomaly IS NOT TRUE
        ORDER BY timestamp ASC, id ASC
        """,
        [track_id],
        log: false
      ).rows
      |> Enum.map(fn [id, timestamp, lon, lat, accuracy] ->
        %Point{id: id, timestamp: timestamp, lon: lon, lat: lat, accuracy: accuracy}
      end)

    segments =
      repo.query!(
        """
        SELECT id, transportation_mode, start_at, end_at, start_index, end_index
        FROM track_segments WHERE track_id = $1
        """,
        [track_id],
        log: false
      ).rows
      |> Enum.map(fn [id, mode, start_at, end_at, start_index, end_index] ->
        %{
          id: id,
          transportation_mode: Segments.int_to_mode(mode),
          start_at: start_at,
          end_at: end_at,
          start_index: start_index,
          end_index: end_index
        }
      end)

    new(points, segments)
  end

  def new(points, segments) do
    points =
      Enum.map(points, &struct(Point, Map.take(&1, [:id, :timestamp, :lon, :lat, :accuracy])))

    segments = Enum.sort_by(segments, &{source_position(&1), &1.id || 0})

    %__MODULE__{
      points: points,
      portions: build_portions(points, segments),
      segment_fingerprint: Enum.map(segments, &fingerprint_segment/1)
    }
  end

  def portions(input), do: input.portions

  def eligible?(%Portion{atlas_mode: mode, points: points}),
    do: not is_nil(mode) and length(points) >= 2

  def eligible?(%__MODULE__{portions: portions}), do: Enum.any?(portions, &eligible?/1)

  def fingerprint_payload(input) do
    %{
      points: Enum.map(input.points, &Point.atlas_shape/1),
      segments: input.segment_fingerprint,
      request: %{shape_match: "map_snap", format: "geojson", include_directions: false}
    }
  end

  def original_coordinates(portion), do: Enum.map(portion.points, &[&1.lon, &1.lat])

  defp source_position(segment) do
    case {Map.get(segment, :start_at), Map.get(segment, :start_index)} do
      {nil, nil} -> :infinity
      {nil, index} -> index
      {time, _} -> epoch(time, :microsecond) / 1_000_000
    end
  end

  defp fingerprint_segment(segment) do
    %{
      start_at: epoch(Map.get(segment, :start_at)),
      end_at: epoch(Map.get(segment, :end_at)),
      start_index: Map.get(segment, :start_index),
      end_index: Map.get(segment, :end_index),
      mode: segment.transportation_mode
    }
  end

  defp build_portions(points, _segments) when length(points) < 2, do: []

  defp build_portions(points, segments) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.map(fn {pair, index} ->
      {Enum.find(segments, &covers_edge?(&1, pair, index)), index}
    end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn group ->
      {owner, first} = hd(group)
      last = elem(List.last(group), 1) + 1
      mode = owner && owner.transportation_mode

      %Portion{
        key: if(owner, do: "segment:#{owner.id}", else: "fallback:#{first}"),
        transportation_mode: mode,
        atlas_mode: ModeMapper.call(mode),
        points: Enum.slice(points, first..last),
        start_index: first,
        end_index: last
      }
    end)
  end

  defp covers_edge?(%{start_at: start_at, end_at: end_at}, [first, second], _index)
       when not is_nil(start_at) and not is_nil(end_at) do
    first.timestamp >= epoch(start_at) and second.timestamp <= epoch(end_at)
  end

  defp covers_edge?(segment, _pair, index) do
    first = Map.get(segment, :start_index)
    last = Map.get(segment, :end_index)
    not is_nil(first) and not is_nil(last) and index >= first and index + 1 <= last
  end

  defp epoch(time, unit \\ :second)
  defp epoch(nil, _unit), do: nil
  defp epoch(%DateTime{} = time, unit), do: DateTime.to_unix(time, unit)

  defp epoch(%NaiveDateTime{} = time, unit),
    do: time |> DateTime.from_naive!("Etc/UTC") |> epoch(unit)

  defp epoch(time, :microsecond) when is_number(time), do: time * 1_000_000
  defp epoch(time, :second) when is_number(time), do: floor(time)
end
