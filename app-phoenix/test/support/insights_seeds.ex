defmodule Dawarich.Test.InsightsSeeds do
  @moduledoc false

  alias Dawarich.Insights.Details
  alias Dawarich.Redis
  alias Dawarich.Test.{StatsSeeds, TripsSeeds}

  @digest_updated ~N[2024-03-05 00:00:00]
  @wire Path.expand("../fixtures/rails_cache/codec-digest.wire", __DIR__)
  @settings %{"timezone" => "Europe/Berlin", "maps" => %{"distance_unit" => "km"}}

  def user!(id \\ 93) do
    TripsSeeds.user!(id, @settings)

    for {month, distance, day} <- [{3, 38_000, "5"}, {4, 12_000, "10"}] do
      StatsSeeds.stat!(id, %{
        year: 2024,
        month: month,
        distance: distance,
        daily_distance: [[day, distance]],
        updated_at: ~N[2024-03-01 00:00:00]
      })
    end

    %{id: id, settings: @settings, plan: 1}
  end

  def yearly_digest!(id \\ 93),
    do: StatsSeeds.digest!(id, %{id: 71, year: 2024, period_type: 1, updated_at: @digest_updated})

  def monthly_digest!(month, updated_at, id \\ 93),
    do:
      StatsSeeds.digest!(id, %{
        year: 2024,
        month: month,
        period_type: 0,
        distance: 777,
        monthly_distances: %{"10" => 777},
        updated_at: updated_at
      })

  def warm!(bytes \\ File.read!(@wire)),
    do: cache!(Details.yearly_key(93, 2024, @digest_updated), bytes)

  def cache!(key, <<0, 17, type, _expires::little-float-64, rest::binary>>) do
    expires = (System.os_time(:second) + 3600) * 1.0

    {:ok, "OK"} =
      Redis.cache_command(["SET", key, <<0, 17, type, expires::little-float-64, rest::binary>>])
  end

  def start_cache! do
    ExUnit.Callbacks.start_supervised!(hd(Redis.cache_child_specs()))
    {:ok, "OK"} = Redis.cache_command(["FLUSHDB"])
    :ok
  end
end
