defmodule Dawarich.AnomalyCase do
  @moduledoc false
  import Dawarich.JobsCase

  def user!(settings \\ %{}) do
    [[id]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES($1,$2,NOW(),NOW()) RETURNING id",
        ["anomaly#{System.unique_integer([:positive])}@example.test", settings]
      )

    id
  end

  def point!(user, timestamp, {longitude, latitude}, opts \\ []) do
    [[id]] =
      rows(
        """
        INSERT INTO points(user_id,timestamp,lonlat,accuracy,tracker_id,velocity,vertical_accuracy,motion_data,raw_data,anomaly,created_at,updated_at)
        VALUES($1,$2,ST_SetSRID(ST_MakePoint($3,$4),4326)::geography,$5,$6,$7,$8,$9,$10,$11,NOW(),NOW()-interval '2 days') RETURNING id
        """,
        [
          user,
          timestamp,
          longitude * 1.0,
          latitude * 1.0,
          Keyword.get(opts, :accuracy, 10),
          Keyword.get(opts, :tracker),
          Keyword.get(opts, :velocity),
          Keyword.get(opts, :vertical_accuracy),
          Keyword.get(opts, :motion, %{}),
          Keyword.get(opts, :raw, %{}),
          Keyword.get(opts, :anomaly, false)
        ]
      )

    id
  end

  def flagged(user),
    do:
      rows("SELECT id FROM points WHERE user_id=$1 AND anomaly IS TRUE ORDER BY id", [user])
      |> List.flatten()

  def filter(user, first, last, opts \\ []) do
    Dawarich.Points.AnomalyFilter.call(
      Dawarich.ScratchRepo,
      user,
      first,
      last,
      Keyword.merge([zone: "UTC", invalidate_dependents: false], opts)
    )
  end

  def trace!(user, entries),
    do: Enum.map(entries, fn {at, coords, opts} -> point!(user, at, coords, opts) end)
end
