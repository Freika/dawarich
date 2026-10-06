defmodule Dawarich.Trips.WebForm do
  @moduledoc false
  alias Dawarich.{TripSettings, TimeZoneName, UserTimeZone}

  def load(repo, user, id, context) do
    with true <- id != nil or active?(user, Map.get_lazy(context, :now, &DateTime.utc_now/0)),
         {:ok, settings} <- TripSettings.read(user.settings),
         {:ok, trip} <- trip(repo, user.id, id),
         {:ok, description} <- Dawarich.Trips.RichContent.read(trip.description) do
      {:ok,
       trip
       |> Map.put(:description, description)
       |> Map.put(:api_key, user.api_key)
       |> Map.put(:style, settings.style)
       |> Map.put(:errors, [])
       |> Map.put(:values, %{
         "name" => trip.name,
         "started_at" => display(repo, user, trip.started_at),
         "ended_at" => display(repo, user, trip.ended_at)
       })}
    else
      {:error, _} = error -> error
      _ -> {:replay, "trip form state"}
    end
  end

  def active?(user, now),
    do: user.active_until != nil and DateTime.compare(user.active_until, now) == :gt

  def invalid(form, errors, values) do
    body = values.attributes.description

    form
    |> Map.put(:errors, errors)
    |> Map.put(:values, values.values)
    |> Map.put(:description, if(body == :unchanged, do: form.description, else: body))
  end

  defp trip(_repo, _user_id, nil),
    do:
      {:ok,
       %{
         id: nil,
         name: nil,
         started_at: nil,
         ended_at: nil,
         description: nil,
         path_json: "",
         plan_json: nil,
         managed: false,
         trek_url: nil
       }}

  defp trip(repo, user_id, id) do
    case repo.query!(
           "SELECT t.id, t.name, t.started_at, t.ended_at, ST_AsGeoJSON(t.path)::jsonb->'coordinates', r.body, t.trip_source_id, t.source_identifier FROM trips t LEFT JOIN action_text_rich_texts r ON r.record_type = 'Trip' AND r.record_id = t.id AND r.name = 'description' WHERE t.id = $1 AND t.user_id = $2",
           [id, user_id],
           log: false
         ).rows do
      [[id, name, started, ended, path, body, _source, identifier]] ->
        with {:ok, plan} <- Dawarich.Trips.PlanRead.load(repo, user_id, id) do
          geojson = if path in [nil, []], do: Dawarich.Trips.PlanGeojson.build(plan)

          {:ok,
           %{
             id: id,
             name: name,
             started_at: started,
             ended_at: ended,
             description: body,
             path_json: if(path, do: Jason.encode!(path), else: ""),
             plan_json: Dawarich.Trips.PlanGeojson.encode(geojson),
             managed:
               Dawarich.ReleaseMigrations.Effects.Support.Ruby.present?(identifier) and
                 plan.trip.source_status == 0,
             trek_url: DawarichWeb.TripPlanItems.trek_url(plan)
           }}
        else
          _ -> {:replay, "planned trip ownership"}
        end

      [] ->
        {:error, :not_found}

      _ ->
        {:replay, "planned trip editor"}
    end
  end

  defp display(_repo, _user, nil), do: nil

  defp display(repo, user, at) do
    zone = UserTimeZone.zone(user.settings)
    zone = if zone in [nil, ""], do: System.get_env("TIME_ZONE", "UTC"), else: zone

    [[local]] =
      repo.query!(
        "SELECT ($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE $2",
        [at, TimeZoneName.to_iana(zone)],
        log: false
      ).rows

    Calendar.strftime(local, "%Y-%m-%dT%H:%M")
  end
end
