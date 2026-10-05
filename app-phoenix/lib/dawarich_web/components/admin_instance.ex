defmodule DawarichWeb.AdminInstance do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.SettingsParts, only: [navigation: 1]

  alias Dawarich.Admin.InstancePage
  alias Dawarich.Geocoding.Providers
  alias DawarichWeb.{AdminJobHealth, AdminSettingField}

  @providers ~w(photon geoapify nominatim locationiq)
  @sections @providers ++ ["rate_limit"]
  @names %{
    "photon" => "Photon",
    "geoapify" => "Geoapify",
    "nominatim" => "Nominatim",
    "locationiq" => "LocationIQ"
  }
  @key_url "https://chibigeo.com/docs/guides/dawarich-self-hosted-geocoding?utm_source=dawarich&utm_medium=app&utm_campaign=geocoding_settings"

  embed_templates "admin_instance/*"

  def section_link(assigns) do
    status = InstancePage.section_status(assigns.data, assigns.item)
    active = assigns.item == assigns.section

    assigns =
      assign(assigns, status: status, active: active, badge: status_badge(assigns.locale, status))

    ~H"""
    <a
      href={"/admin/settings?section=" <> @item}
      data-turbo="false"
      class={"flex items-center gap-3 rounded-box border p-3 transition-colors " <> if(@active, do: "border-primary/60 bg-base-200", else: "border-base-content/10 hover:border-base-content/25")}
      aria-current={@active && "page"}
      data-testid={"instance-settings-section-" <> @item}
      data-status={@status}
    >
      <.icon name={section_icon(@item)} class="size-5 shrink-0 text-base-content/70" />
      <span class="font-medium flex-1 truncate">{section_title(@locale, @item)}</span>
      <span :if={@badge} class="tooltip tooltip-left" data-tip={elem(@badge, 2)}>
        <.icon name={elem(@badge, 0)} class={"size-4 " <> elem(@badge, 1)} />
        <span class="sr-only">{elem(@badge, 2)}</span>
      </span>
    </a>
    """
  end

  defp sections, do: @sections
  defp providers, do: @providers
  defp key_url, do: @key_url

  defp section_title(_locale, section) when section in @providers, do: @names[section]

  defp section_title(locale, "rate_limit"),
    do: t(locale, "admin.settings.show.geocoding.rate_limit", %{})

  defp section_title(locale, "points"), do: t(locale, "admin.settings.show.points.title", %{})
  defp section_icon("rate_limit"), do: "clock"
  defp section_icon("points"), do: "map-pin"
  defp section_icon(_), do: "globe"

  defp in_use?(data, section),
    do: data.geocoding.enabled and to_string(Map.get(data.geocoding, :provider)) == section

  defp komoot?(data),
    do: in_use?(data, "photon") and Providers.komoot?(:photon, data.geocoding.host)

  defp pinned_var(data) do
    if data.geocoding.enabled and data.geocoding.source == :env do
      primary = %{
        photon: "photon_api_host",
        nominatim: "nominatim_api_host",
        geoapify: "geoapify_api_key",
        locationiq: "locationiq_api_key"
      }

      data.fields[primary[data.geocoding.provider]].env_var
    end
  end

  defp status_badge(locale, :attention),
    do: {"triangle-alert", "text-warning", t(locale, "admin.settings.show.nav_attention", %{})}

  defp status_badge(locale, :in_use),
    do: {"circle-check", "text-success", t(locale, "admin.settings.show.geocoding.in_use", %{})}

  defp status_badge(locale, :pinned),
    do: {"lock", "text-base-content/70", t(locale, "admin.settings.show.nav_pinned", %{})}

  defp status_badge(_, nil), do: nil
end
