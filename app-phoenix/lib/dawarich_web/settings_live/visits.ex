defmodule DawarichWeb.SettingsLive.Visits do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.SettingsParts, only: [navigation: 1]
  import DawarichWeb.VisitRedetectPanel, only: [panel: 1]
  alias Dawarich.Visits.WebSettings

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    page =
      WebSettings.page(
        user,
        WebSettings.load(Dawarich.Repo, user.id),
        socket.assigns.now,
        socket.assigns.self_hosted
      )

    {:ok,
     assign(socket, Map.put(page, :page_title, text(socket.assigns.locale, "visit_detection")))}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :fields, [
        {"visit_radius_meters", "visit_radius_meters",
         "points_within_this_radius_are_treated_as_the_same_visit", assigns.policy.stay_radius_m,
         5, 500},
        {"visit_min_points", "minimum_points_to_count_as_a_visit",
         "lower_more_visits_suggested_including_brief_stops_default_3", assigns.policy.min_points,
         2, 20},
        {"visit_min_duration_minutes", "minimum_visit_duration_minutes",
         "skip_stops_shorter_than_this_raise_to_ignore_short_drive",
         div(assigns.policy.min_dwell_s, 60), 1, 60}
      ])

    ~H"""
    <div class="min-h-content w-full my-5">
      <.page_header title={text(@locale, "visit_detection")} />
      <.navigation
        locale={@locale}
        active="visits"
        self_hosted={@self_hosted}
        admin={@current_user.admin == true}
        two_factor={@two_factor}
      />
      <div class="card bg-base-200 shadow-xl mb-6" data-controller="visit-detection-settings">
        <form
          id="visit-detection-settings"
          phx-update="ignore"
          action="/settings/visits"
          accept-charset="UTF-8"
          method="post"
        >
          <input type="hidden" name="_method" value="patch" />
          <input
            :if={@rails_csrf_token}
            type="hidden"
            name="authenticity_token"
            value={@rails_csrf_token}
          />
          <div class="card-body">
            <h2 class="text-2xl font-bold mb-2">
              {text(@locale, "tune_how_dawarich_decides_where_you_actually_were")}
            </h2>
            <p class="text-sm opacity-80 mb-4">
              {text(@locale, "these_settings_control_how_the_app_groups_your_gps_points")}
            </p>
            <div :for={{name, label, hint, value, min, max} <- @fields} class="form-control mb-4">
              <label for={"settings_" <> name} class="label-text font-semibold">{text(@locale, label)}</label>
              <input
                type="number"
                name={"settings[" <> name <> "]"}
                id={"settings_" <> name}
                value={value}
                min={min}
                max={max}
                step="1"
                class="input input-bordered w-32"
              />
              <span class="text-xs opacity-70 mt-1">{text(@locale, hint)}</span>
            </div>
            <div class="card-actions justify-end">
              <input
                type="submit"
                name="commit"
                value={text(@locale, "save_settings")}
                class="btn btn-primary"
                data-disable-with={text(@locale, "save_settings")}
              />
            </div>
          </div>
        </form>
      </div>
      <.panel
        locale={@locale}
        cooldown={@cooldown}
        restricted={@restricted}
        available_at={@available_at}
        rails_csrf_token={@rails_csrf_token}
      />
    </div>
    """
  end

  defp text(locale, key), do: t(locale, "settings.visits.show." <> key, %{})
end
