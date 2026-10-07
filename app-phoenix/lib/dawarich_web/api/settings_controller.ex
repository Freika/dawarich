defmodule DawarichWeb.Api.SettingsController do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Settings.{Api, Progress}
  alias DawarichWeb.Api.Respond

  @scalar ~w(timezone meters_between_routes minutes_between_routes fog_of_war_meters time_threshold_minutes merge_threshold_minutes route_opacity route_color track_color preferred_map_layer points_rendering_mode live_map_enabled immich_url immich_api_key photoprism_url photoprism_api_key speed_colored_routes speed_color_scale fog_of_war_threshold fog_of_war_mode maps_v2_style maps_maplibre_style maps_maplibre_tiles_url maps_maplibre_tiles_fallback globe_projection min_minutes_spent_in_city gps_filtering_enabled point_dragging_enabled points_tiled_rendering)
  @arrays ~w(enabled_map_layers places_tag_filters enabled_transportation_modes)
  @pro ~w(immich_url immich_api_key photoprism_url photoprism_api_key maps_maplibre_custom_theme maps_maplibre_tiles_url maps_maplibre_tiles_fallback route_color track_color)
  @tokens ~w(bg water parks buildings railway boundaries road_motorway road_primary road_secondary road_tertiary road_residential road_default)
  def init(action), do: action
  def call(conn, :general), do: general(conn)

  def call(conn, action) do
    ctx = Api.context(conn)
    user = conn.assigns.api_user

    result =
      case action do
        :index -> Api.index(Dawarich.Repo, user, ctx)
        :settings -> Api.index(Dawarich.Repo, user, ctx)
        :update -> Api.update(Dawarich.Repo, user, conn.assigns.api_params, ctx)
        :transportation_recalculation_status -> Progress.show(user, ctx)
        :progress -> Progress.show(user, ctx)
      end

    {_, status, body} = result
    Respond.json(conn, status, Api.term(body))
  rescue
    _ -> Respond.json(conn, 500, Api.failure())
  end

  def permit(raw, restricted) do
    attrs =
      Enum.reduce(@arrays, scalars(raw, @scalar), fn key, acc ->
        if is_list(raw[key]) and Enum.all?(raw[key], &scalar?/1),
          do: Map.put(acc, key, raw[key]),
          else: acc
      end)

    attrs =
      if is_map(raw["maps"]),
        do: Map.put(attrs, "maps", maps(raw["maps"], restricted)),
        else: attrs

    attrs =
      if is_map(raw["maps_maplibre_custom_theme"]),
        do:
          Map.put(attrs, "maps_maplibre_custom_theme", theme(raw["maps_maplibre_custom_theme"])),
        else: attrs

    attrs =
      if is_binary(attrs["maps_maplibre_tiles_url"]),
        do:
          Map.update!(attrs, "maps_maplibre_tiles_url", fn url ->
            if String.trim(url) == "", do: nil, else: String.trim(url)
          end),
        else: attrs

    if restricted do
      attrs = Map.drop(attrs, @pro)

      if attrs["maps_maplibre_style"] == "custom",
        do: Map.delete(attrs, "maps_maplibre_style"),
        else: attrs
    else
      attrs
    end
  end

  defp maps(raw, restricted) do
    attrs =
      if raw["distance_unit"] in ~w(km mi),
        do: %{"distance_unit" => raw["distance_unit"]},
        else: %{}

    Enum.reduce(~w(hidden_tile_categories disabled_poi_groups), attrs, fn key, acc ->
      if not restricted and is_list(raw[key]) and Enum.all?(raw[key], &scalar?/1),
        do: Map.put(acc, key, raw[key]),
        else: acc
    end)
  end

  defp theme(raw) do
    if is_map(raw["tokens"]),
      do: Map.put(scalars(raw, ["base"]), "tokens", scalars(raw["tokens"], @tokens)),
      else: scalars(raw, ["base"])
  end

  def term(%{"settings" => settings} = body) when not is_map_key(body, "capabilities") do
    keys =
      if Map.has_key?(body, "message"),
        do: ~w(message settings status recalculation_triggered),
        else: ~w(settings status)

    {:object,
     Enum.map(keys, fn key ->
       {key,
        if(key == "settings",
          do: {:object, Enum.map(Api.fields(), &{&1, settings[&1]})},
          else: body[key]
        )}
     end)}
  end

  def term(body), do: body

  def scalars(attrs, keys),
    do: Map.take(attrs, keys) |> Map.filter(fn {_, value} -> scalar?(value) end)

  defp scalar?(value),
    do: is_nil(value) or is_binary(value) or is_number(value) or is_boolean(value)

  def valid_tiles?(nil), do: true

  def valid_tiles?(url) when is_binary(url) do
    uri = URI.parse(url)
    locator = url |> String.split(~r/[?#]/) |> hd() |> String.downcase()

    style =
      valid_style_syntax?(url) and not String.match?(url, ~r/[{}]/) and
        not Enum.any?(~w(.png .jpg .jpeg .webp .mvt .pbf), &String.ends_with?(locator, &1)) and
        ((uri.scheme in ~w(http https) and uri.host not in [nil, ""]) or
           (is_nil(uri.scheme) and uri.host in [nil, ""] and
              String.starts_with?(uri.path || "", "/")))

    style or Enum.all?(~w({z} {x} {y}), &String.contains?(url, &1))
  rescue
    _ -> false
  end

  def valid_tiles?(_), do: false

  defp valid_style_syntax?(url) do
    uri = URI.parse(url)

    fragment =
      case String.split(url, "#", parts: 2) do
        [_, value] -> value
        _ -> ""
      end

    String.match?(url, ~r/\A[\x00-\x7f]*\z/) and
      String.match?(uri.path || "", ~r/\A(?:%[0-9a-fA-F]{2}|[A-Za-z0-9._~!$&'()*+,;=:@\/-])*\z/) and
      String.match?(
        fragment,
        ~r/\A(?:%[0-9a-fA-F]{2}|[A-Za-z0-9._~!$&'()*+,;=:@\/?-])*\z/
      ) and
      valid_authority?(uri.authority)
  end

  defp valid_authority?(nil), do: true

  defp valid_authority?(authority) do
    case Regex.run(~r/\A(?:([^@]*)@)?(\[[^\]]+\]|[^:]*)(?::[0-9]*)?\z/, authority) do
      [_, userinfo, host] ->
        String.match?(userinfo, ~r/\A(?:%[0-9a-fA-F]{2}|[A-Za-z0-9._~!$&'()*+,;=:-])*\z/) and
          valid_host?(host)

      _ ->
        false
    end
  end

  defp valid_host?("[" <> literal) do
    address = String.trim_trailing(literal, "]")

    case :inet.parse_strict_address(String.to_charlist(address)) do
      {:ok, ip} when tuple_size(ip) == 8 -> true
      _ -> String.match?(address, ~r/\Av[0-9a-fA-F]+\.[A-Za-z0-9._~!$&'()*+,;=:-]+\z/)
    end
  end

  defp valid_host?(host),
    do: String.match?(host, ~r/\A(?:%[0-9a-fA-F]{2}|[A-Za-z0-9._~!$&'()*+,;=-])*\z/)

  defp general(conn) do
    params = conn.assigns.api_params
    check = assign(conn, :api_params, Map.delete(params, "locale"))

    with :ok <- DawarichWeb.RailsForm.admission(check, allowed_overrides: ["PATCH"]),
         {:ok, settings} <-
           Api.general(Dawarich.Repo, conn.assigns.current_user, params, Api.context(conn)) do
      locale = settings["locale"] || "en"

      notice =
        DawarichWeb.Translate.t(locale, "controllers.settings.general.settings_updated", %{})

      conn
      |> DawarichWeb.RailsSession.stage(%{
        "flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}
      })
      |> put_resp_header("location", DawarichWeb.RequestURL.base(conn) <> "/settings/general")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("text/html")
      |> send_resp(302, "")
      |> halt()
    else
      _ -> DawarichWeb.StandaloneError.respond(conn, "settings_general_failure", 422)
    end
  end
end
