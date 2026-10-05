defmodule Dawarich.ReleaseJobs do
  @moduledoc false

  alias Dawarich.ReleaseOperations, as: Ops

  @families ~w(DataMigrations::BackfillFamiliesForFamilyPlanJob DataMigrations::BackfillFamilyMemberEntitlementsJob)
  @deferred %{
    "DataMigrations::AddPointDimensionColumnsJob" => :a12h,
    "DataMigrations::DropLegacyLatLonJob" => :a12h,
    "DataMigrations::BackfillAchievementsJob" => :a12d2
  }
  @a12 Map.keys(@deferred)
  @classes @families ++
             @a12 ++
             ~w(DataMigrations::BackfillPointDimensionsJob DataMigrations::BackfillPointCountryIdJob
                DataMigrations::FixRouteOpacityJob DataMigrations::BackfillOnboardingCompletedJob
                DataMigrations::DestroyOrphanedTracksJob Tracks::DeduplicationJob
                DataMigrations::BackfillPlacesUserIdJob DataMigrations::BackfillPlaceNameLocksJob
                TrackSegments::TimeAnchorBackfillJob DataMigrations::BackfillTransportationModesJob
                Visits::FleetRedetectJob DataMigrations::CleanupNullIslandJob
                DataMigrations::BackfillMotionDataJob DataMigrations::BackfillAltitudeJob
                TransportationModes::ImportBackfillJob
                DataMigrations::RecalculateAnomaliesJob DataMigrations::RecalculatePerTrackerTracksJob)

  def classes, do: @classes

  def decode("DataMigrations::RecalculateAnomaliesJob", []),
    do: recalculation(Ops.Anomalies, %{"limit" => 2})

  def decode("DataMigrations::RecalculatePerTrackerTracksJob", []),
    do: recalculation(Ops.PerTracker, %{"user_id" => nil})

  def decode("DataMigrations::BackfillPointDimensionsJob", []),
    do: points("dimensions", 50_000, false)

  def decode("DataMigrations::BackfillPointCountryIdJob", []),
    do: points("country", 50_000, false)

  def decode("DataMigrations::BackfillPointCountryIdJob", [
        nil,
        size,
        %{"repair_collisions" => true, "_aj_ruby2_keywords" => ["repair_collisions"]} = keywords
      ])
      when is_integer(size) and size > 0 and map_size(keywords) == 2,
      do: points("country", size, true)

  def decode("DataMigrations::FixRouteOpacityJob", []), do: once(Ops.RouteOpacity)

  def decode("DataMigrations::BackfillOnboardingCompletedJob", []),
    do: once(Ops.OnboardingCompleted)

  def decode("DataMigrations::DestroyOrphanedTracksJob", []), do: once(Ops.OrphanedTracks)
  def decode("DataMigrations::BackfillPlacesUserIdJob", []), do: once(Ops.PlacesUserId)
  def decode("DataMigrations::BackfillPlaceNameLocksJob", []), do: once(Ops.PlaceNameLocks)

  def decode("Tracks::DeduplicationJob", [user_id]) when is_integer(user_id) and user_id > 0,
    do: {:ok, Ops.TracksDedup, %{"version" => 1, "user_id" => user_id}}

  def decode("TrackSegments::TimeAnchorBackfillJob", []),
    do: chain(Ops.TimeAnchor, %{"from_id" => 0})

  def decode("DataMigrations::BackfillTransportationModesJob", []),
    do: chain(Ops.Transportation, %{"scope" => "missing", "from_track_id" => 0})

  def decode("Visits::FleetRedetectJob", []),
    do: chain(Ops.VisitsFleetRedetect, %{"after_id" => 0, "started_at" => nil, "offset" => 0})

  def decode("DataMigrations::CleanupNullIslandJob", []),
    do: chain(Ops.NullIsland, %{"after_id" => 0})

  def decode("DataMigrations::BackfillMotionDataJob", []),
    do: chain(Ops.MotionData, %{"after_id" => 0, "batch_size" => 1_000})

  def decode("DataMigrations::BackfillAltitudeJob", []),
    do: chain(Ops.Altitude, %{"phase" => "users", "after_id" => 0})

  def decode(class, []) when class in @families do
    if Dawarich.ReleaseMigration.self_hosted?(), do: :skip, else: {:error, :cloud_family_backfill}
  end

  def decode(class, []) when class in @a12,
    do: {:deferred, Map.fetch!(@deferred, class), %{"version" => 1}}

  def decode("TransportationModes::ImportBackfillJob", [import_id])
      when is_integer(import_id) and import_id > 0,
      do: {:deferred, :a7, %{"version" => 1, "import_id" => import_id}}

  def decode(class, _arguments) when class in @classes, do: {:error, :invalid_arguments}
  def decode(_class, _arguments), do: {:error, :unknown_class}

  defp points(phase, size, repair) do
    chain(Ops.PointBackfill, %{
      "phase" => phase,
      "start_id" => nil,
      "batch_size" => size,
      "repair_collisions" => repair
    })
  end

  defp once(worker), do: {:ok, worker, %{"version" => 1}}

  defp recalculation(worker, payload) do
    zone = Dawarich.TimeZoneName.to_iana(System.get_env("TIME_ZONE", "Europe/Berlin"))

    request =
      Map.merge(payload, %{"source_job_id" => Ecto.UUID.generate(), "ambient_zone" => zone})

    {:ok, args} = worker.args_from_command(1, request)
    {:ok, worker, Map.put(args, "operation_id", Ecto.UUID.generate())}
  end

  defp chain(worker, cursor),
    do:
      {:ok, worker, %{"version" => 1, "operation_id" => Ecto.UUID.generate(), "cursor" => cursor}}
end
