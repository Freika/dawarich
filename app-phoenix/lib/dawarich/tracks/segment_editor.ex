defmodule Dawarich.Tracks.SegmentEditor do
  @moduledoc false
  alias Dawarich.Tracks.{SegmentEditEffects, Reprocessor, Settings, Store}
  alias Dawarich.TrackSegmentPage
  alias Dawarich.Transportation.{DominantMode, Segments}

  @segment_columns ~w(id track_id start_index end_index start_at end_at distance duration avg_speed max_speed transportation_mode confidence confidence_score corrected_at source updated_at)a

  def apply_override(repo, user, track_id, id, mode, ctx) do
    transaction(repo, fn ->
      {track, segment} = owned!(repo, user, track_id, id)

      if mode in Settings.enabled_modes(user) do
        now = DateTime.to_naive(ctx.now)

        repo.query!(
          "UPDATE track_segments SET transportation_mode=$2,corrected_at=$3,confidence=2,confidence_score=1.0,source='user',updated_at=$3 WHERE id=$1",
          [id, Segments.mode_to_int(mode), now]
        )

        mode = dominant(repo, track_id)
        save_mode(repo, user, track, mode, now)

        fresh = %{
          segment
          | transportation_mode: mode_for(repo, id),
            corrected_at: now,
            confidence: 2,
            confidence_score: 1.0,
            source: "user",
            updated_at: now
        }

        render(
          repo,
          {:ok,
           %{
             segment: fresh,
             track: Map.put(track, :dominant_mode, current_mode(repo, track_id)),
             page: page!(repo, user, track_id),
             reset: false
           }},
          ctx
        )
      else
        render(repo, {:error, %{error_code: :mode_not_enabled}}, ctx)
      end
    end)
  end

  def reset_to_auto(repo, user, track_id, id, ctx) do
    case repo.transaction(fn ->
           {track, _segment} = owned!(repo, user, track_id, id)
           now = DateTime.to_naive(ctx.now)

           repo.query!(
             "UPDATE track_segments SET corrected_at=NULL,source='inferred',updated_at=$2 WHERE id=$1",
             [id, now]
           )

           Reprocessor.reprocess!(repo, user, track, ctx.now)

           mode =
             repo |> Segments.load_segments_for_dominant_mode!(track_id) |> DominantMode.pick()

           if mode,
             do:
               SegmentEditEffects.reset!(repo, user.id, %{
                 updated: [track.id],
                 stamps: [track.start_at, track.end_at]
               })

           page = page!(repo, user, track_id)

           render(
             repo,
             {:ok,
              %{
                segment: nil,
                track: Map.put(track, :dominant_mode, current_mode(repo, track_id)),
                page: page,
                reset: true
              }},
             ctx
           )
         end) do
      {:ok, result} -> result
      {:error, :rails} -> :rails
      {:error, :not_found} -> :not_found
    end
  rescue
    _ -> {:error, %{error_code: :reprocess_failed}}
  end

  defp page!(repo, user, track_id) do
    case TrackSegmentPage.load(user, track_id, repo) do
      {:ok, page} -> page
      :rails -> repo.rollback(:rails)
    end
  end

  defp owned!(repo, user, track_id, id) do
    track = Store.get(repo, track_id, true)
    if is_nil(track) or track.user_id != user.id, do: repo.rollback(:not_found)

    case repo.query!(
           "SELECT #{Enum.join(@segment_columns, ",")} FROM track_segments WHERE id=$1 AND track_id=$2 FOR UPDATE",
           [id, track_id]
         ).rows do
      [row] ->
        segment = Map.new(Enum.zip(@segment_columns, row))
        if not valid_segment?(segment) or not valid_track?(repo, track), do: repo.rollback(:rails)
        {track, segment}

      [] ->
        repo.rollback(:not_found)
    end
  end

  defp valid_segment?(s) do
    anchored =
      (s.start_at != nil and s.end_at != nil) or (s.start_index != nil and s.end_index != nil)

    anchored and s.transportation_mode in 0..10 and
      Enum.all?(
        [s.start_index, s.end_index, s.distance, s.duration, s.avg_speed, s.max_speed],
        &(is_nil(&1) or &1 >= 0)
      ) and
      (is_nil(s.start_index) or is_nil(s.end_index) or s.end_index >= s.start_index) and
      (is_nil(s.start_at) or is_nil(s.end_at) or DateTime.compare(s.end_at, s.start_at) != :lt)
  end

  defp valid_track?(repo, track) do
    track.start_at != nil and track.end_at != nil and
      Enum.all?([track.distance, track.duration, track.avg_speed], &(not is_nil(&1) and &1 >= 0)) and
      repo.query!("SELECT original_path IS NOT NULL FROM tracks WHERE id=$1", [track.id]).rows ==
        [[true]]
  end

  defp dominant(repo, id) do
    repo.query!(
      "SELECT transportation_mode,distance,duration FROM track_segments WHERE track_id=$1",
      [id]
    ).rows
    |> Enum.map(fn [mode, distance, duration] ->
      %{transportation_mode: Segments.int_to_mode(mode), distance: distance, duration: duration}
    end)
    |> DominantMode.pick()
  end

  defp save_mode(_repo, _user, _track, nil, _now), do: :ok

  defp save_mode(repo, user, track, mode, now) do
    repo.query!(
      "UPDATE tracks SET dominant_mode=$2,updated_at=$3,lock_version=lock_version+1 WHERE id=$1 AND dominant_mode IS DISTINCT FROM $2",
      [track.id, Segments.mode_to_int(mode), now]
    )

    SegmentEditEffects.write!(repo, user.id, %{
      updated: [track.id],
      stamps: [track.start_at, track.end_at]
    })
  end

  defp mode_for(repo, id) do
    [[mode]] =
      repo.query!("SELECT transportation_mode FROM track_segments WHERE id=$1", [id]).rows

    Segments.int_to_mode(mode)
  end

  defp current_mode(repo, id) do
    [[mode]] = repo.query!("SELECT dominant_mode FROM tracks WHERE id=$1", [id]).rows
    Segments.int_to_mode(mode)
  end

  defp render(repo, {status, result} = outcome, ctx) do
    case Map.get(ctx, :render) do
      nil ->
        outcome

      fun ->
        case fun.(outcome) do
          {:ok, response} -> {status, Map.put(result, :response, response)}
          :rails -> repo.rollback(:rails)
        end
    end
  end

  defp transaction(repo, fun) do
    case repo.transaction(fun) do
      {:ok, result} -> result
      {:error, :rails} -> :rails
      {:error, :not_found} -> :not_found
    end
  rescue
    _ in [Postgrex.Error, DBConnection.ConnectionError] -> :rails
  end
end
