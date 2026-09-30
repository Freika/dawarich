defmodule Dawarich.EnhancedImport.Extract do
  @moduledoc false

  alias Dawarich.EnhancedImport.{Gpx, PlaceWriter, SourceFile}
  alias Dawarich.{RubyInteger, Storage}

  @element_counts ~w(waypoints_seen trackpoints_seen route_points_seen)

  def process(repo, import, storage, event_id, deadline) do
    if without_waypoints?(import.raw_data) do
      %{}
    else
      tmp = Storage.tmp_dir!(storage, "extract-#{event_id}")

      try do
        path = SourceFile.fetch!(repo, import.id, storage, tmp)

        state =
          Gpx.reduce(path, PlaceWriter.new(import), fn place, state ->
            check_deadline!(deadline)
            PlaceWriter.upsert(repo, state, place)
          end)

        if state.count > 0, do: %{"places" => state.count}, else: %{}
      after
        File.rm_rf!(tmp)
      end
    end
  end

  defp without_waypoints?(%{} = counts),
    do:
      Enum.any?(@element_counts, &Map.has_key?(counts, &1)) and
        RubyInteger.to_i(counts["waypoints_seen"]) == 0

  defp without_waypoints?(_raw_data), do: false

  defp check_deadline!(%{at: at, minutes: minutes}) do
    if System.monotonic_time(:millisecond) >= at,
      do: raise("GPX extraction did not finish within #{minutes} minutes")
  end
end
