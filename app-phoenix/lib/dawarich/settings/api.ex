defmodule Dawarich.Settings.Api do
  @moduledoc false
  alias Dawarich.{Entitlements, I18n, RubyInteger, UserSettings}
  alias Dawarich.Settings.Progress
  alias DawarichWeb.Api.SettingsController

  @fields ~w(fog_of_war_meters preferred_map_layer time_threshold_minutes merge_threshold_minutes live_map_enabled track_color immich_url immich_api_key photoprism_url photoprism_api_key airtrail_url airtrail_api_key maps distance_unit visits_suggestions_enabled fog_of_war_threshold fog_of_war_mode enabled_map_layers places_tag_filters maps_maplibre_style maps_maplibre_tiles_url maps_maplibre_tiles_fallback maps_maplibre_custom_theme globe_projection enabled_transportation_modes min_minutes_spent_in_city gps_filtering_enabled timezone visit_radius_meters visit_min_points visit_min_duration_minutes point_dragging_enabled meters_between_routes speed_colored_routes points_rendering_mode minutes_between_routes route_opacity route_color speed_color_scale points_tiled_rendering)
  @modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)
  @gated ["Heatmap", "Fog of War", "Scratch map"]

  def modes, do: @modes
  def failure, do: %{"status" => 500, "error" => "Internal Server Error"}

  def context(conn),
    do:
      Map.merge(
        %{now: DateTime.utc_now(), self_hosted?: DawarichWeb.LayoutAssigns.self_hosted?()},
        conn.assigns[:api_context] || %{}
      )

  def guard(user, ctx, active? \\ false) do
    cond do
      is_nil(user) or user.status == 3 -> Dawarich.Imports.Api.guard(user, ctx, false, false)
      active? -> Dawarich.Imports.Api.guard(user, ctx, false, false)
      true -> :ok
    end
  end

  def restricted?(repo, user, ctx),
    do: not Entitlements.full_access?(repo, user, ctx.self_hosted?, ctx.now)

  def index(repo, user, ctx) do
    with :ok <- guard(user, ctx),
         do:
           {:ok, 200,
            %{
              "settings" => config(read(repo, user.id), restricted?(repo, user, ctx)),
              "status" => "success"
            }}
  rescue
    _ -> {:error, 500, failure()}
  end

  def read(repo, id) do
    [[raw]] = repo.query!("SELECT settings FROM users WHERE id=$1", [id], log: false).rows
    raw
  end

  def config(raw, restricted) do
    s = UserSettings.safe(raw)

    maps =
      if restricted,
        do: Map.drop(s["maps"], ~w(hidden_tile_categories disabled_poi_groups)),
        else: s["maps"]

    layers = List.wrap(s["enabled_map_layers"])
    layers = if "Routes" in layers, do: layers ++ ["Tracks"], else: layers
    layers = Enum.uniq(layers -- ["Routes"])
    layers = if restricted, do: layers -- @gated, else: layers

    colors =
      if not Map.has_key?(raw, "track_color") and
           "Routes" in List.wrap(raw["enabled_map_layers"]),
         do: s["route_color"],
         else: s["track_color"]

    Map.new(@fields, &{&1, s[&1]})
    |> Map.merge(%{
      "maps" => maps,
      "distance_unit" => maps["distance_unit"] || "km",
      "enabled_map_layers" => layers,
      "track_color" => colors,
      "meters_between_routes" => positive(s["meters_between_routes"], 500),
      "minutes_between_routes" => min(positive(s["minutes_between_routes"], 30), 1440),
      "time_threshold_minutes" => clamp(s["time_threshold_minutes"], 1, 1440),
      "merge_threshold_minutes" => RubyInteger.to_i(s["merge_threshold_minutes"]),
      "visits_suggestions_enabled" => s["visits_suggestions_enabled"] == "true",
      "fog_of_war_mode" =>
        if(s["fog_of_war_mode"] in ~w(points hexagons), do: s["fog_of_war_mode"], else: "points"),
      "globe_projection" =>
        if(restricted, do: false, else: UserSettings.cast(s["globe_projection"])),
      "maps_maplibre_tiles_fallback" =>
        UserSettings.cast(s["maps_maplibre_tiles_fallback"]) || false,
      "enabled_transportation_modes" => effective_modes(s["enabled_transportation_modes"]),
      "places_tag_filters" => filters(s["places_tag_filters"]),
      "min_minutes_spent_in_city" => RubyInteger.to_i(s["min_minutes_spent_in_city"] || 60),
      "gps_filtering_enabled" =>
        is_nil(s["gps_filtering_enabled"]) or UserSettings.cast(s["gps_filtering_enabled"]),
      "visit_radius_meters" => clamp(s["visit_radius_meters"], 5, 500),
      "visit_min_points" => clamp(s["visit_min_points"], 2, 20),
      "visit_min_duration_minutes" => clamp(s["visit_min_duration_minutes"] || 5, 1, 60),
      "point_dragging_enabled" => UserSettings.cast(s["point_dragging_enabled"]) || false,
      "points_tiled_rendering" => true
    })
  end

  def fields, do: @fields
  defdelegate term(body), to: SettingsController

  def update(repo, user, params, ctx) do
    with :ok <- guard(user, ctx, true),
         {:ok, attrs} <- Dawarich.Points.ApiWrites.required(params, "settings") do
      restricted = restricted?(repo, user, ctx)
      attrs = SettingsController.permit(attrs, restricted)

      if SettingsController.valid_tiles?(attrs["maps_maplibre_tiles_url"]) do
        save(repo, user, attrs, ctx, restricted)
      else
        {:error, 422,
         %{"message" => t("something_went_wrong"), "errors" => [t("tile_url_error")]}}
      end
    end
  rescue
    _ -> {:error, 500, failure()}
  end

  defp save(repo, user, attrs, ctx, restricted) do
    case repo.transaction(fn ->
           [[before]] =
             repo.query!("SELECT settings FROM users WHERE id=$1 FOR UPDATE", [user.id],
               log: false
             ).rows

           if Map.has_key?(attrs, "enabled_transportation_modes") and
                Dawarich.Transportation.RecalculationStatus.in_progress?(user.id),
              do:
                repo.rollback(
                  {:error, 423,
                   %{
                     "message" =>
                       I18n.en!("services.users.settings_updater.recalculation_in_progress"),
                     "status" => "locked"
                   }}
                )

           raw = attrs["enabled_transportation_modes"]

           if raw != nil and raw != [] and Enum.all?(raw, &(&1 not in @modes)),
             do:
               repo.rollback(
                 {:error, 422,
                  %{
                    "message" => t("something_went_wrong"),
                    "errors" => [
                      I18n.en!(
                        "services.users.settings_updater.enable_at_least_one_transportation_mode"
                      )
                    ]
                  }}
               )

           attrs =
             if Map.has_key?(attrs, "timezone") and not zone?(repo, attrs["timezone"]),
               do: Map.delete(attrs, "timezone"),
               else: attrs

           after_settings =
             Enum.reduce(attrs, before, fn
               {"maps", maps}, acc -> Map.put(acc, "maps", Map.merge(acc["maps"] || %{}, maps))
               {key, value}, acc -> Map.put(acc, key, value)
             end)

           after_settings = if restricted, do: gate(after_settings, attrs), else: after_settings
           after_settings = sanitize(after_settings)

           repo.query!(
             "UPDATE users SET settings=$2,updated_at=$3 WHERE id=$1",
             [user.id, after_settings, DateTime.to_naive(ctx.now)],
             log: false
           )

           months = Progress.rebucket(repo, user.id, before, after_settings, ctx)
           {before, after_settings, months}
         end) do
      {:ok, {before, after_settings, months}} ->
        Progress.rebuild(repo, user.id, months, ctx)

        if Enum.any?(
             ~w(immich_url immich_api_key photoprism_url photoprism_api_key),
             &(before[&1] != after_settings[&1])
           ),
           do:
             Map.get(ctx, :invalidate_photos, &Dawarich.Photos.ProviderCache.invalidate/1).(
               user.id
             )

        triggered = Progress.callbacks(repo, user.id, before, after_settings, attrs, ctx)
        Map.get(ctx, :after_commit, fn -> :ok end).()

        {:ok, 200,
         %{
           "message" => t("settings_updated"),
           "settings" => config(after_settings, restricted),
           "status" => "success",
           "recalculation_triggered" => triggered
         }}

      {:error, result} ->
        result
    end
  end

  def general(repo, user, attrs, ctx) do
    attrs =
      Map.take(
        attrs,
        ~w(timezone locale supporter_email supporter_github_username monthly_digest_emails_enabled yearly_digest_emails_enabled news_emails_enabled show_supporter_badge)
      )

    attrs =
      if attrs["locale"] in DawarichWeb.Locale.locales(),
        do: attrs,
        else: Map.delete(attrs, "locale")

    attrs =
      Enum.reduce(
        ~w(monthly_digest_emails_enabled yearly_digest_emails_enabled news_emails_enabled show_supporter_badge),
        attrs,
        fn key, acc ->
          if Map.has_key?(acc, key), do: Map.update!(acc, key, &UserSettings.cast/1), else: acc
        end
      )

    with {:ok, 200, _} <- save(repo, user, attrs, ctx, false) do
      if Enum.any?(
           ~w(monthly_digest_emails_enabled yearly_digest_emails_enabled),
           &Map.has_key?(attrs, &1)
         ),
         do:
           repo.query!(
             "UPDATE users SET settings=settings-'digest_emails_enabled' WHERE id=$1",
             [user.id],
             log: false
           )

      {:ok, read(repo, user.id)}
    end
  rescue
    _ -> {:error, 500, failure()}
  end

  def zone?(repo, value) when is_binary(value) do
    repo.query!(
      "SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=$1)",
      [Dawarich.TimeZoneName.to_iana(value)],
      log: false
    ).rows == [[true]]
  end

  def zone?(_, _), do: false

  defp sanitize(settings),
    do:
      Enum.reduce(~w(immich_url photoprism_url), settings, fn key, acc ->
        if is_binary(acc[key]),
          do: Map.update!(acc, key, &String.replace(&1, ~r{/+$}, "")),
          else: acc
      end)

  defp gate(s, attrs) do
    s =
      if Map.has_key?(s, "enabled_map_layers"),
        do: Map.update!(s, "enabled_map_layers", &(&1 -- @gated)),
        else: s

    if Map.has_key?(attrs, "globe_projection"), do: Map.put(s, "globe_projection", false), else: s
  end

  def effective_modes(nil), do: @modes
  def effective_modes([]), do: @modes

  def effective_modes(values) do
    modes = Enum.filter(Enum.uniq(List.wrap(values)), &(&1 in @modes))
    if modes == [], do: @modes, else: modes
  end

  defp filters(nil), do: nil

  defp filters(values),
    do:
      Enum.map(List.wrap(values), fn value ->
        if value == "untagged", do: value, else: RubyInteger.to_i(value)
      end)

  defp positive(value, default),
    do: max(RubyInteger.to_i(value), 0) |> then(&if(&1 > 0, do: &1, else: default))

  defp clamp(value, low, high), do: min(max(RubyInteger.to_i(value), low), high)
  defp t(key), do: I18n.en!("controllers.api.v1.settings." <> key)
end
