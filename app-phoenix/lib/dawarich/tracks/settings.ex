defmodule Dawarich.Tracks.Settings do
  @moduledoc false

  alias Dawarich.RubyInteger
  alias Dawarich.Transportation.Segments
  alias Dawarich.Trips.Calculation

  def load!(repo, user_id) do
    %{rows: [[settings]]} =
      repo.query!("SELECT settings FROM users WHERE id = $1", [user_id], log: false)

    %{id: user_id, settings: if(is_map(settings), do: settings, else: %{})}
  end

  def find(repo, user_id) do
    case repo.query!(
           "SELECT settings, status FROM users WHERE id = $1 AND deleted_at IS NULL",
           [user_id],
           log: false
         ).rows do
      [[settings, status]] ->
        %{id: user_id, settings: if(is_map(settings), do: settings, else: %{}), status: status}

      [] ->
        nil
    end
  end

  def minutes_between_routes(%{settings: settings}),
    do: Calculation.minutes_between_routes(settings)

  def meters_between_routes(%{settings: settings}) do
    meters = RubyInteger.to_i(settings["meters_between_routes"])
    if meters > 0, do: meters, else: 500
  end

  def enabled_modes(%{settings: settings}), do: Segments.enabled_modes(settings)
end
