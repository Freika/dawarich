defmodule Dawarich.Admin.BackgroundCommands do
  @moduledoc false
  alias Dawarich.Jobs.Ownership
  alias Dawarich.{Repo, UserTimeZone}

  @imports %{
    "start_immich_import" => {"imports.immich_geodata", "/imports"},
    "start_photoprism_import" => {"imports.photoprism_geodata", "/imports"},
    "start_airtrail_import" => {"imports.airtrail_flights", "/settings/integrations"},
    "start_teslamate_sync" =>
      {"imports.teslamate_sync", "/settings/integrations?service=teslamate"}
  }
  @reverse ~w(start_reverse_geocoding continue_reverse_geocoding)
  def names, do: Map.keys(@imports) ++ @reverse

  def call(actor, name, context) do
    repo = Map.get(context, :repo, Repo)

    result =
      repo.transaction(fn ->
        with [[settings]] <-
               repo.query!(
                 "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR SHARE",
                 [actor.id],
                 log: false
               ).rows,
             true <- context[:oidc] != true,
             true <- context[:self_hosted] == true or Map.has_key?(@imports, name) do
          dispatch(repo, actor.id, settings, name, context)
        else
          _ -> {:handoff, :actor}
        end
      end)

    case result do
      {:ok, outcome} -> outcome
      {:error, _} -> {:terminal, :command}
    end
  end

  defp dispatch(repo, id, settings, name, context) when is_map_key(@imports, name) do
    {type, path} = @imports[name]

    if Ownership.lock(repo, "command:" <> type) == :oban do
      zone = UserTimeZone.name(settings)
      payload = %{"user_id" => id}

      payload =
        if type in ~w(imports.immich_geodata imports.photoprism_geodata),
          do: Map.put(payload, "time_zone", zone),
          else: payload

      metadata = %{
        "producer" => "Settings::BackgroundJobsController",
        "locale" => context.locale,
        "time_zone" => zone
      }

      repo.query!(
        "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),$1,1,$2,$3,$4,now())",
        [type, payload, metadata, id],
        log: false
      )

      {:ok, path}
    else
      {:handoff, :owner}
    end
  end

  defp dispatch(repo, id, _settings, name, context) when name in @reverse do
    if Ownership.lock(repo, "command:geocoding.reverse_point") == :oban do
      args = %{
        "user_id" => id,
        "force" => name == "start_reverse_geocoding",
        "after_id" => 0,
        "locale" => context.locale
      }

      case Oban.insert(
             Map.get(context, :oban, Oban),
             Dawarich.Admin.BackgroundGeocodingWorker.new(args)
           ) do
        {:ok, _} -> {:ok, "/settings/background_jobs"}
        {:error, _} -> repo.rollback(:enqueue)
      end
    else
      {:handoff, :owner}
    end
  end

  defp dispatch(_, _, _, _, _), do: {:invalid, :job_name}
end
