defmodule Dawarich.Imports.IntegrationCommands do
  @moduledoc false
  alias Dawarich.{Jobs.Ownership, TimeZoneName, UserSettings}

  @jobs %{
    "start_immich_import" => "imports.immich_geodata",
    "start_photoprism_import" => "imports.photoprism_geodata",
    "start_airtrail_import" => "imports.airtrail_flights",
    "start_teslamate_sync" => "imports.teslamate_sync",
    "start_reverse_geocoding" => "geocoding.reverse_point",
    "continue_reverse_geocoding" => "geocoding.reverse_point"
  }

  def enqueue(repo, user_id, job, opts \\ [])

  def enqueue(repo, user_id, job, opts) when is_binary(job) do
    case Map.fetch(@jobs, job) do
      {:ok, kind} -> enqueue_kind(repo, user_id, kind, job, opts)
      :error -> {:error, :unknown_job}
    end
  end

  def enqueue(_repo, _user_id, _job, _opts), do: {:error, :unknown_job}

  defp enqueue_kind(repo, user_id, kind, job, opts) do
    repo.transaction(fn ->
      if Ownership.lock(repo, "command:" <> kind) != :oban,
        do: repo.rollback(:not_owned)

      settings =
        case repo.query!(
               "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR SHARE",
               [user_id],
               log: false
             ).rows do
          [[settings]] when is_map(settings) or is_nil(settings) -> UserSettings.safe(settings)
          _ -> repo.rollback(:not_found)
        end

      zone = UserSettings.safe(settings)["timezone"] |> TimeZoneName.to_iana()
      Dawarich.Imports.ZonePeriod.load!(zone)
      event = Ecto.UUID.generate()
      payload = %{"user_id" => user_id}

      payload =
        if kind in ~w(imports.immich_geodata imports.photoprism_geodata),
          do: Map.put(payload, "time_zone", zone),
          else: payload

      if kind == "geocoding.reverse_point" do
        config = Dawarich.Geocoding.Config.resolve(repo)

        if job == "start_reverse_geocoding" and config[:provider] in [:geoapify, :locationiq] and
             not Keyword.get_lazy(opts, :self_hosted, &Dawarich.ReleaseMigration.self_hosted?/0),
           do: repo.rollback(:paid_provider_force_rerun_blocked)

        args =
          Map.merge(payload, %{
            "force" => job == "start_reverse_geocoding",
            "after_id" => 0,
            "locale" =>
              Keyword.get(opts, :locale, Dawarich.Mail.ExploreFeatures.locale(settings, nil))
          })

        Oban.insert!(
          Keyword.get(opts, :oban, Oban),
          Dawarich.Admin.BackgroundGeocodingWorker.new(args)
        )
      else
        repo.query!(
          "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6,now())",
          [
            Ecto.UUID.dump!(event),
            kind,
            payload,
            %{"producer" => "Phoenix integration trigger"},
            user_id,
            "integration-trigger:" <> event
          ],
          log: false
        )
      end

      :queued
    end)
  rescue
    _ -> {:error, :enqueue_failed}
  end
end
