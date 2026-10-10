defmodule Dawarich.Maps.Dependencies.Trip do
  @moduledoc false
  alias Dawarich.{Maps, TripPage}

  def config(scope, id, opts \\ []) do
    with {:ok, data} <- read(scope, id, opts), do: {:ok, data["config"]}
  end

  def read(scope, id, opts \\ [])

  def read(scope, id, opts) when is_integer(id) and id > 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Maps.with_actor(
      scope,
      fn user ->
        case TripPage.load(user, id, now) do
          {:ok, page} -> {:ok, project(page)}
          _ -> {:error, :not_found}
        end
      end,
      now: now
    )
  end

  def read(_, _, _), do: {:error, :invalid}

  def view(scope, id, opts \\ [])

  def view(scope, id, opts) when is_integer(id) and id > 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Maps.with_actor(
      scope,
      fn actor ->
        case TripPage.load(actor, id, now) do
          {:ok, page} ->
            {:ok,
             %{
               config: project(page)["config"],
               presentation: present(page),
               studio: Map.take(page.studio, [:themes, :print_order_url])
             }}

          _ ->
            {:error, :not_found}
        end
      end,
      now: now
    )
  end

  def view(_, _, _), do: {:error, :invalid}

  def presentation(scope, id, opts \\ [])

  def presentation(scope, id, opts) when is_integer(id) and id > 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Maps.with_actor(
      scope,
      fn actor ->
        case TripPage.load(actor, id, now) do
          {:ok, page} -> {:ok, present(page)}
          _ -> {:error, :not_found}
        end
      end,
      now: now
    )
  end

  def presentation(_, _, _), do: {:error, :invalid}

  def present(page) do
    days =
      Enum.map(page.days, fn day ->
        %{
          day
          | photos:
              Enum.map(day.photos, fn photo ->
                %{
                  id: photo.id,
                  source: photo.source,
                  url:
                    "/native/map/data/photos/" <>
                      URI.encode_www_form(to_string(photo.id)) <>
                      "/thumbnail?source=" <> URI.encode_www_form(photo.source)
                }
              end)
        }
      end)

    links = Map.filter(page.photos.links, fn {_source, url} -> safe_source_link?(url) end)

    page
    |> Map.take(
      ~w(id name distance countries flags settings iana started_at ended_at duration recalculating shared has_path map_state days day_notes plan now plan_on_map plan_toggle future_start description)a
    )
    |> Map.put(:days, days)
    |> Map.put(:plan, %{page.plan | source: safe_plan_source(page.plan.source)})
    |> Map.put(:photos, %{
      sources: Enum.filter(page.photos.sources, &Map.has_key?(links, &1)),
      links: links
    })
  end

  defp safe_plan_source(%{base_url: url} = source) do
    if safe_source_link?(url),
      do: Map.take(source, [:id, :provider, :base_url, :status, :last_synced_at]),
      else: nil
  end

  defp safe_plan_source(_), do: nil

  defp safe_source_link?(url) when is_binary(url) do
    uri = URI.parse(url)
    keys = URI.decode_query(uri.query || "") |> Map.keys()

    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.userinfo == nil and
      not Enum.any?(
        keys,
        &(String.downcase(&1) in ~w(api_key password token access_token authorization))
      )
  rescue
    _ -> false
  end

  defp safe_source_link?(_), do: false

  defp project(page) do
    config = %{
      "tripId" => page.id,
      "title" => page.name,
      "range" => %{
        "startAt" => DawarichWeb.HumanDatetime.iso8601(page.started_at),
        "endAt" => DawarichWeb.HumanDatetime.iso8601(page.ended_at),
        "timezone" => page.iana
      },
      "routeOptions" => %{
        "distanceThresholdMeters" => page.settings.meters,
        "timeThresholdMinutes" => page.settings.minutes
      },
      "styleName" => page.settings.style,
      "photosEnabled" => page.settings.photos,
      "flightsEnabled" => page.settings.airtrail,
      "planEnabled" => page.plan_on_map,
      "mapState" => to_string(page.map_state)
    }

    %{
      "config" => config,
      "path" => decode(page.path_json, []),
      "deviceWindows" => decode(page.windows_json, []),
      "plan" => decode(page.plan_json, nil)
    }
  end

  defp decode(value, fallback) when value in [nil, ""], do: fallback
  defp decode(value, _fallback), do: Jason.decode!(value)
end
