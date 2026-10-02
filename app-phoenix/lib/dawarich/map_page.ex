defmodule Dawarich.MapPage do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.{Entitlements, MapWindow, Repo, SubscriptionToken}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)
  @fog_modes ~w(points hexagons)
  @live_share 3
  @max_id 9_223_372_036_854_775_807
  @numeric ~r/\A\s*[+-]?\d/

  def modes, do: @modes

  def load(user, params, opts) do
    now = Keyword.fetch!(opts, :now)
    self_hosted = Keyword.fetch!(opts, :self_hosted)
    family = Keyword.fetch!(opts, :family)
    env = Keyword.get(opts, :env, System.get_env())
    settings = if is_map(user.settings), do: user.settings, else: %{}

    with {:ok, place} <- place(user.id, params["place_id"]) do
      picked = import_row(user.id, params["import_id"])
      {full, plan} = Entitlements.access(user, self_hosted, now)
      tags = tags(user.id)
      window = MapWindow.build(params, settings, now, picked && picked.range, env)

      {:ok,
       settings
       |> settings_view(full, env)
       |> Map.merge(%{
         api_key: to_string(user.api_key),
         window: window,
         import_id: picked && picked.id,
         plan: plan,
         full_access: full,
         upgrade_url: upgrade_url(user, now, self_hosted, "map", "maplibre"),
         badge_url: upgrade_url(user, now, self_hosted, "badge", "pro_badge"),
         place: place,
         tags: tags,
         timeline_tags: Enum.take(tags, 8),
         themes: poster_themes(),
         live_share: live_share?(user.id, now),
         demo_data: demo_data?(user.id),
         print_order_url: env["PRINT_ORDER_URL"] || "https://prints.dawarich.app/api/orders",
         family: family,
         features_json: features_json(family),
         posters: Dawarich.MapGallery.posters(user.id),
         route_videos: Dawarich.MapGallery.route_videos(user.id, window.zone),
         posters_stream: Dawarich.RailsMessages.stream_name([{:user, user.id}, "posters"])
       })}
    end
  end

  def member?(list, key) when is_list(list), do: key in list
  def member?(text, key) when is_binary(text), do: String.contains?(text, key)
  def member?(_value, _key), do: false

  def poster_themes do
    case :persistent_term.get({__MODULE__, :themes}, nil) do
      nil ->
        tap(
          read_themes(Dawarich.RailsRoot.join("public/poster_themes")),
          &:persistent_term.put({__MODULE__, :themes}, &1)
        )

      themes ->
        themes
    end
  end

  def read_themes(dir) do
    for path <- dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort(),
        {:ok, %{} = data} <- [path |> File.read!() |> Jason.decode()],
        do: %{key: Path.basename(path, ".json"), name: data["name"]}
  end

  defp place(_user_id, nil), do: {:ok, nil}
  defp place(_user_id, value) when not is_binary(value), do: :not_found

  defp place(user_id, value) do
    cond do
      not Ruby.present?(value) -> {:ok, nil}
      not Regex.match?(@numeric, value) -> :not_found
      true -> find_place(user_id, DawarichWeb.Params.ruby_to_i(value))
    end
  end

  defp find_place(user_id, id) when id in 1..@max_id do
    from(p in "places",
      where: p.user_id == ^user_id and p.id == ^id,
      select: %{
        id: p.id,
        lat: fragment("ST_Y(?::geometry)", p.lonlat),
        lon: fragment("ST_X(?::geometry)", p.lonlat),
        latitude: p.latitude,
        longitude: p.longitude
      }
    )
    |> Repo.one()
    |> case do
      nil ->
        :not_found

      row ->
        {:ok,
         %{
           id: row.id,
           lat: row.lat || Decimal.to_float(row.latitude),
           lon: row.lon || Decimal.to_float(row.longitude)
         }}
    end
  end

  defp find_place(_user_id, _id), do: :not_found

  defp import_row(user_id, value) when is_binary(value) do
    with true <- Ruby.present?(value) and Regex.match?(@numeric, value),
         id when id in 1..@max_id <- DawarichWeb.Params.ruby_to_i(value),
         [id, min, max] <-
           Repo.query!(
             "SELECT i.id, min(p.timestamp), max(p.timestamp) FROM imports i LEFT JOIN points p ON p.import_id = i.id " <>
               "WHERE i.user_id = $1 AND i.id = $2 GROUP BY i.id",
             [user_id, id]
           ).rows
           |> List.first() do
      %{id: id, range: min && {min, max}}
    else
      _ -> nil
    end
  end

  defp import_row(_user_id, _value), do: nil

  defp tags(user_id) do
    from(t in "tags",
      where: t.user_id == ^user_id,
      order_by: t.name,
      select: %{id: t.id, name: t.name, color: t.color, icon: t.icon}
    )
    |> Repo.all()
  end

  defp live_share?(user_id, now) do
    at = DateTime.to_naive(now)

    from(s in "shared_links",
      where:
        s.user_id == ^user_id and s.resource_type == @live_share and is_nil(s.revoked_at) and
          (is_nil(s.expires_at) or s.expires_at > ^at)
    )
    |> Repo.exists?()
  end

  defp demo_data?(user_id),
    do: from(i in "imports", where: i.user_id == ^user_id and i.demo) |> Repo.exists?()

  defp features_json(family) do
    geocoding = Dawarich.Geocoding.Config.resolve(Repo).enabled
    Jason.encode!(Jason.OrderedObject.new(reverse_geocoding: geocoding, family: family))
  end

  defp upgrade_url(_user, _now, true, _medium, _content), do: ""

  defp upgrade_url(user, now, false, medium, content) do
    utm = %{
      "utm_campaign" => "lite_upgrade",
      "utm_content" => content,
      "utm_medium" => medium,
      "utm_source" => "app"
    }

    SubscriptionToken.url(user, now) <> "&" <> DawarichWeb.Params.to_query(utm)
  end

  defp settings_view(settings, full, env) do
    maps = if is_map(settings["maps"]), do: settings["maps"], else: %{}

    maps =
      if full, do: maps, else: Map.drop(maps, ["hidden_tile_categories", "disabled_poi_groups"])

    %{
      live_map: Map.get(settings, "live_map_enabled", true),
      airtrail: Ruby.present?(settings["airtrail_url"]),
      fog_mode:
        if(settings["fog_of_war_mode"] in @fog_modes,
          do: settings["fog_of_war_mode"],
          else: "points"
        ),
      hidden_tile_categories: maps["hidden_tile_categories"] || [],
      disabled_poi_groups: maps["disabled_poi_groups"] || [],
      transport_modes: transport_modes(settings["enabled_transportation_modes"]),
      immich: Ruby.present?(settings["immich_url"]) and Ruby.present?(settings["immich_api_key"]),
      immich_url: settings["immich_url"],
      timezone: MapWindow.user_zone(settings, env)
    }
  end

  defp transport_modes(raw) do
    wanted = for value <- List.wrap(raw), is_binary(value), do: value

    case Enum.filter(@modes, &(&1 in wanted)) do
      [] -> @modes
      modes -> modes
    end
  end
end
