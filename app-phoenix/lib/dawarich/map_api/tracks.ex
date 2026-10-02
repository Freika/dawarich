defmodule Dawarich.MapApi.Tracks do
  @moduledoc false

  alias Dawarich.{Repo, RubyInteger}
  alias Dawarich.MapApi.{Clip, Params, TrackRecord}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def index(user, params, _now) do
    with {:ok, {where, args}} <- range(user.id, params) do
      [[count]] = Repo.query!("SELECT COUNT(*) FROM tracks t " <> where, args).rows
      page = Params.page(params["page"])
      per = Params.per_page(params["per_page"], 500)
      sql = where <> " ORDER BY t.start_at DESC LIMIT #{per} OFFSET #{(page - 1) * per}"

      {:ok,
       {:object,
        [
          {"type", "FeatureCollection"},
          {"features", TrackRecord.features(TrackRecord.rows(sql, args), false)}
        ]},
       [
         {"x-current-page", Integer.to_string(page)},
         {"x-total-pages", Integer.to_string(div(count + per - 1, per))},
         {"x-total-count", Integer.to_string(count)}
       ], 200}
    end
  end

  def show(user, params, now) do
    case TrackRecord.rows("WHERE t.user_id = $1 AND t.id = $2", [
           user.id,
           RubyInteger.to_i(params["id"])
         ]) do
      [] ->
        :missing

      [track] ->
        [feature] = TrackRecord.features([track], true)

        with {:ok, feature} <- Clip.apply(feature, track, user, params, now),
             do:
               {:ok, {:object, [{"type", "FeatureCollection"}, {"features", [feature]}]}, [], 200}
    end
  end

  defp range(user_id, params) do
    if Ruby.present?(params["start_at"]) and Ruby.present?(params["end_at"]) do
      with {:ok, from} <- Params.zoned_time(params["start_at"]),
           {:ok, to} <- Params.zoned_time(params["end_at"]) do
        {:ok,
         {"WHERE t.user_id = $1 AND t.end_at >= ($2::text::timestamptz AT TIME ZONE 'UTC') " <>
            "AND t.start_at <= ($3::text::timestamptz AT TIME ZONE 'UTC')", [user_id, from, to]}}
      end
    else
      {:ok, {"WHERE t.user_id = $1", [user_id]}}
    end
  end
end
