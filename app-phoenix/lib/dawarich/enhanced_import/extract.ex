defmodule Dawarich.EnhancedImport.Extract do
  @moduledoc false

  alias Dawarich.EnhancedImport.{Adapters, Deadline, ItemWriter, PlaceWriter, SourceFile}
  alias Dawarich.{RubyInteger, Storage}

  @element_counts ~w(waypoints_seen trackpoints_seen route_points_seen)
  @chunk 500

  def process(repo, import, storage, event_id, deadline, context \\ %{}) do
    import = Map.put_new(import, :source, 4)

    if import.source == 4 and without_waypoints?(import.raw_data) do
      %{}
    else
      tmp = Storage.tmp_dir!(storage, "extract-#{event_id}")

      try do
        Deadline.run(fn -> extract(repo, import, storage, tmp, deadline, context) end, deadline)
      after
        File.rm_rf!(tmp)
      end
    end
  end

  defp extract(repo, import, storage, tmp, deadline, context) do
    path = SourceFile.fetch!(repo, import.id, storage, tmp)

    if import.source == 4 do
      gpx(repo, import, path, deadline)
    else
      ItemWriter.reduce(repo, import, path, context, deadline)
    end
  end

  defp gpx(repo, import, path, deadline) do
    guard = Map.get(import, :fence, fn fun -> fun.() end)

    {state, chunk, _size} =
      Adapters.reduce(path, import, %{}, {PlaceWriter.new(import), [], 0}, fn
        place, {state, chunk, size} when size + 1 < @chunk ->
          {state, [place | chunk], size + 1}

        place, {state, chunk, _size} ->
          {write(repo, state, [place | chunk], deadline, guard), [], 0}
      end)

    state = write(repo, state, chunk, deadline, guard)

    if state.count > 0, do: %{"places" => state.count}, else: %{}
  end

  defp write(_repo, state, [], _deadline, _guard), do: state

  defp write(repo, state, chunk, deadline, guard) do
    places = Enum.reverse(chunk)

    Enum.reduce(places, guard.(fn -> PlaceWriter.prefetch(repo, state, places) end), fn place,
                                                                                        state ->
      Deadline.check!(deadline)
      guard.(fn -> PlaceWriter.upsert(repo, state, place) end)
    end)
  end

  defp without_waypoints?(%{} = counts),
    do:
      Enum.any?(@element_counts, &Map.has_key?(counts, &1)) and
        RubyInteger.to_i(counts["waypoints_seen"]) == 0

  defp without_waypoints?(_raw_data), do: false
end
