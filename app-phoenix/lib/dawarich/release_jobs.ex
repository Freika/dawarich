defmodule Dawarich.ReleaseJobs do
  @moduledoc false

  alias Dawarich.ReleaseOperations, as: Ops

  @families ~w(DataMigrations::BackfillFamiliesForFamilyPlanJob DataMigrations::BackfillFamilyMemberEntitlementsJob)
  @classes @families ++
             ~w(DataMigrations::AddPointDimensionColumnsJob DataMigrations::DropLegacyLatLonJob
                DataMigrations::BackfillPointDimensionsJob DataMigrations::BackfillPointCountryIdJob
                DataMigrations::FixRouteOpacityJob DataMigrations::BackfillOnboardingCompletedJob
                DataMigrations::DestroyOrphanedTracksJob Tracks::DeduplicationJob
                DataMigrations::BackfillPlacesUserIdJob DataMigrations::BackfillPlaceNameLocksJob
                TrackSegments::TimeAnchorBackfillJob DataMigrations::BackfillTransportationModesJob
                Visits::FleetRedetectJob DataMigrations::CleanupNullIslandJob
                DataMigrations::BackfillMotionDataJob DataMigrations::BackfillAltitudeJob
                TransportationModes::ImportBackfillJob DataMigrations::BackfillAchievementsJob
                DataMigrations::RecalculateAnomaliesJob DataMigrations::RecalculatePerTrackerTracksJob)

  def classes, do: @classes

  def decode("DataMigrations::AddPointDimensionColumnsJob", []), do: once(Ops.AddPointDimensions)
  def decode("DataMigrations::DropLegacyLatLonJob", []), do: once(Ops.DropLegacyCoordinates)

  def decode("DataMigrations::BackfillAchievementsJob", []),
    do: {:ok, Ops.Achievements, %{"version" => 1, "event_id" => Ecto.UUID.generate()}}

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
    if Dawarich.ReleaseMigration.self_hosted?() do
      :skip
    else
      phase = if class == hd(@families), do: "families", else: "entitlements"
      zone = Dawarich.TimeZoneName.to_iana(System.get_env("TIME_ZONE", "Europe/Berlin"))
      chain(__MODULE__.FamilyBackfill, %{"phase" => phase, "after_id" => 0, "time_zone" => zone})
    end
  end

  def decode("TransportationModes::ImportBackfillJob", [import_id])
      when is_integer(import_id) and import_id > 0 do
    zone = Dawarich.TimeZoneName.to_iana(System.get_env("TIME_ZONE", "Europe/Berlin"))

    {:ok, args} =
      Ops.ImportBackfill.args_from_command(1, %{"import_id" => import_id, "ambient_zone" => zone})

    {:ok, Ops.ImportBackfill, Map.put(args, "event_id", Ecto.UUID.generate())}
  end

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

defmodule Dawarich.ReleaseJobs.FamilyBackfill do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 26

  alias Dawarich.Families.{AutoCreateWorker, MemberSync}
  alias Dawarich.ReleaseOperations

  @families """
  SELECT u.id FROM users u
  WHERE u.deleted_at IS NULL AND u.plan=2 AND u.id>$1
    AND NOT EXISTS(SELECT 1 FROM family_memberships m WHERE m.user_id=u.id)
    AND NOT EXISTS(SELECT 1 FROM families f WHERE f.creator_id=u.id)
  ORDER BY u.id LIMIT 500
  """
  @entitlements "SELECT id FROM families WHERE id>$1 ORDER BY id LIMIT 200"

  def command_type, do: "release.family_backfill"

  def args_from_command(1, %{"phase" => phase, "after_id" => id, "time_zone" => zone} = payload)
      when map_size(payload) == 3 and phase in ["families", "entitlements"] and
             is_integer(id) and id >= 0 and is_binary(zone) do
    Dawarich.Imports.ZonePeriod.load!(zone)
    {:ok, %{"version" => 1, "cursor" => payload}}
  rescue
    _ -> {:error, "invalid_payload"}
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(job), do: ReleaseOperations.run(Dawarich.Jobs.repo(), Oban, __MODULE__, job)

  def step(repo, %{cursor: %{"phase" => "families", "after_id" => after_id} = cursor} = op) do
    ReleaseOperations.commit(repo, op, fn ->
      ids = ReleaseOperations.ids(repo, @families, [after_id])

      for id <- ids do
        Oban.insert!(
          op.oban,
          AutoCreateWorker.new(%{
            "event_id" => Ecto.UUID.generate(),
            "user_id" => id,
            "time_zone" => cursor["time_zone"]
          })
        )
      end

      advance(cursor, ids, 500)
    end)
  end

  def step(repo, %{cursor: %{"phase" => "entitlements", "after_id" => after_id} = cursor} = op) do
    ids = ReleaseOperations.ids(repo, @entitlements, [after_id])

    for id <- ids,
        do: MemberSync.run(repo, id, notify: false, time_zone: cursor["time_zone"])

    ReleaseOperations.commit(repo, op, fn -> advance(cursor, ids, 200) end)
  end

  defp advance(cursor, ids, size) do
    if length(ids) < size, do: :done, else: {%{cursor | "after_id" => List.last(ids)}, 0}
  end
end
