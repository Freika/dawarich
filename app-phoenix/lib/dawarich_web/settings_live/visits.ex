defmodule DawarichWeb.SettingsLive.Visits do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.CoreComponents, only: [input: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.SettingsParts, only: [navigation: 1]
  import DawarichWeb.VisitRedetectPanel, only: [panel: 1]
  alias Dawarich.Settings
  alias Dawarich.Visits.WebSettings

  @fields [
    {:visit_radius_meters, "visit_radius_meters",
     "points_within_this_radius_are_treated_as_the_same_visit", 5, 500},
    {:visit_min_points, "minimum_points_to_count_as_a_visit",
     "lower_more_visits_suggested_including_brief_stops_default_3", 2, 20},
    {:visit_min_duration_minutes, "minimum_visit_duration_minutes",
     "skip_stops_shorter_than_this_raise_to_ignore_short_drive", 1, 60}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: text(socket.assigns.locale, "visit_detection"),
       fields: @fields,
       queued: false
     )
     |> load_page(nil)}
  end

  @impl true
  def handle_event("change", %{"settings" => params}, socket),
    do: {:noreply, assign(socket, :form, to_form(params, as: :settings))}

  def handle_event("save", %{"settings" => params}, socket) do
    {:ok, _} = Settings.update_visits(socket.assigns.current_scope, params)

    {:noreply,
     socket
     |> load_page(nil)
     |> put_flash(:notice, flash(socket, "settings.visits.visit_detection_settings_updated"))}
  end

  def handle_event("redetect", _params, socket) do
    form = socket.assigns.form

    case Settings.request_visit_redetection(socket.assigns.current_scope) do
      :ok ->
        {:noreply,
         socket
         |> load_page(form)
         |> assign(:queued, true)
         |> put_flash(
           :notice,
           flash(
             socket,
             "visits.redetections.re_detection_queued_we_ll_notify_you_when_it_finishes"
           )
         )}

      :cooldown ->
        {:noreply,
         put_flash(
           socket,
           :alert,
           flash(socket, "visits.redetections.re_detect_ran_recently_try_again_in_an_hour")
         )}
    end
  end

  defp load_page(socket, form) do
    user = socket.assigns.current_user

    page =
      WebSettings.page(
        user,
        WebSettings.load(Dawarich.Repo, user.id),
        DateTime.utc_now(),
        socket.assigns.self_hosted
      )

    socket
    |> assign(page)
    |> assign(:form, form || to_form(values(page.policy), as: :settings))
  end

  defp values(policy),
    do: %{
      "visit_radius_meters" => policy.stay_radius_m,
      "visit_min_points" => policy.min_points,
      "visit_min_duration_minutes" => div(policy.min_dwell_s, 60)
    }

  defp flash(socket, key), do: t(socket.assigns.locale, "controllers." <> key, %{})
  defp text(locale, key), do: t(locale, "settings.visits.show." <> key, %{})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-content w-full my-5">
      <.page_header title={text(@locale, "visit_detection")} />
      <.navigation
        locale={@locale}
        active="visits"
        self_hosted={@self_hosted}
        admin={@current_user.admin == true}
        two_factor={@two_factor}
        native
      />
      <div class="card bg-base-200 shadow-xl mb-6">
        <.form for={@form} id="visit-detection-settings" phx-change="change" phx-submit="save">
          <div class="card-body">
            <h2 class="text-2xl font-bold mb-2">
              {text(@locale, "tune_how_dawarich_decides_where_you_actually_were")}
            </h2>
            <p class="text-sm opacity-80 mb-4">
              {text(@locale, "these_settings_control_how_the_app_groups_your_gps_points")}
            </p>
            <div :for={{name, label, hint, min, max} <- @fields} class="mb-4">
              <.input
                field={@form[name]}
                type="number"
                label={text(@locale, label)}
                min={min}
                max={max}
                step="1"
                class="input input-bordered w-32"
              />
              <span class="text-xs opacity-70 mt-1">{text(@locale, hint)}</span>
            </div>
            <div class="card-actions justify-end">
              <button
                type="submit"
                class="btn btn-primary"
                phx-disable-with={text(@locale, "save_settings")}
              >
                {text(@locale, "save_settings")}
              </button>
            </div>
          </div>
        </.form>
      </div>
      <.panel
        locale={@locale}
        cooldown={@cooldown}
        queued={@queued}
        restricted={@restricted}
        available_at={@available_at}
      />
    </div>
    """
  end
end
