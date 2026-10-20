defmodule DawarichWeb.EmbeddedStudios do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.{Assets, Icon, MapGalleryCards, RouteVideoCard}
  alias Phoenix.LiveView.JS

  embed_templates "embedded_studios/*"

  def poster_config(locale, url) do
    DawarichWeb.NativePosterStudio.config(locale, url)
    |> Jason.decode!()
    |> Map.put("controls", DawarichWeb.NativePosterSections.control_options(locale))
    |> Jason.encode!()
  end

  attr :locale, :string, required: true
  attr :current, :string, required: true

  def switcher(assigns) do
    ~H"""
    <div
      class="join shrink-0"
      role="group"
      aria-label={t(@locale, "shared.studio_switcher.studios", %{})}
    >
      <button
        :for={kind <- ~w(poster video)}
        type="button"
        class={"btn btn-xs join-item gap-1 " <> if(kind == @current, do: "btn-active", else: "btn-ghost")}
        aria-current={if kind == @current, do: "true"}
        data-testid={"studio-switch-" <> kind}
        data-native-poster-switch-video={@current == "poster" and kind == "video"}
        data-native-video-switch={@current == "video" and kind == "poster"}
        phx-mounted={JS.ignore_attributes(["hidden", "disabled"])}
      >
        <Icon.icon name={if kind == "poster", do: "image", else: "video"} class="h-3.5 w-3.5" />
        <span class="hidden sm:inline">{t(@locale, "shared.studio_switcher." <> kind, %{})}</span>
      </button>
    </div>
    """
  end

  defp p(locale, key, bindings \\ %{}), do: t(locale, "posters.studio." <> key, bindings)
  defp v(locale, key), do: t(locale, "route_videos.studio." <> key, %{})

  defp tokens do
    [
      {"bg", "background"},
      {"water", "water"},
      {"parks", "parks"},
      {"buildings", "buildings"},
      {"railway", "railways"},
      {"boundaries", "boundaries"},
      {"road_motorway", "motorway_roads"},
      {"road_primary", "primary_roads"},
      {"road_residential", "residential_roads"},
      {"road_default", "other_roads"},
      {"route", "track"},
      {"text", "text"}
    ]
  end

  defp layers do
    [
      {"roads", "roads", true},
      {"water", "water", true},
      {"landuse", "parks_land_use", true},
      {"buildings", "buildings", false},
      {"rail", "railways", false},
      {"boundaries", "boundaries", false}
    ]
  end

  defp formats(locale) do
    for {key, ratio, preview} <- [
          {"portrait", "9:16", "h-8 w-[18px]"},
          {"landscape", "16:9", "h-6 w-11"},
          {"square", "1:1", "h-8 w-8"}
        ] do
      label = v(locale, "format_" <> key)

      %{
        key: key,
        label: label,
        short: label |> String.split(" · ", parts: 2) |> hd(),
        ratio: ratio,
        preview: preview
      }
    end
  end
end
