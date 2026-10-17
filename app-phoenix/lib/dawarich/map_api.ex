defmodule Dawarich.MapApi do
  @moduledoc false

  alias Dawarich.{I18n, RailsTime}
  alias Dawarich.MapApi.{Points, Tracks}

  def read(action, user, params, now) do
    if Enum.all?(params, fn {_key, value} -> is_binary(value) or is_nil(value) end),
      do: RailsTime.with_zone(user.timezone, fn -> run(action, user, params, now) end),
      else: {:replay, "map parameter shape"}
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end

  defp run(:points, user, params, now) do
    case Points.index(user, params, now) do
      :bad_bbox ->
        {:ok, {:object, [{"error", I18n.en!("controllers.api.v1.points.invalid_bounding_box")}]},
         [], 400}

      result ->
        result
    end
  end

  defp run(:tracks, user, params, now), do: Tracks.index(user, params, now)
  defp run(:track, user, params, now), do: Tracks.show(user, params, now)
  defp run(:track_points, user, params, _now), do: Points.track(user, params)
end
