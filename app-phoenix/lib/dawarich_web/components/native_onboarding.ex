defmodule DawarichWeb.NativeOnboarding do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.OnboardingScreens, only: [track_screen: 1, tm: 2]

  alias DawarichWeb.Icon
  alias Phoenix.LiveView.JS

  @screens ~w(onboarding-choice-screen onboarding-import-screen onboarding-track-screen)
  @formats [
    {"google_maps", "records_json_semantic_history_phone_takeout_json"},
    {"gpx", "track_files_gpx"},
    {"geojson", "feature_collections_json"},
    {"owntracks", "recorder_files_rec"},
    {"kml", "kml_files_kml_kmz"}
  ]

  def show(screen, event \\ nil) do
    js =
      JS.hide(to: Enum.map_join(@screens -- [screen], ", ", &"##{&1}"))
      |> JS.show(to: "##{screen}")

    if event, do: JS.dispatch(js, "dawarich:track", detail: %{event: event}), else: js
  end

  def modal(assigns) do
    %{current_user: user, navbar: %{family: family}} = assigns

    assigns =
      assign(assigns,
        family_card: family.available or family.member,
        family_href: if(family.available, do: "/family", else: "/family/new"),
        demo_loaded: assigns.navbar.imports.demo,
        formats: @formats,
        legacy_trial: user.status == 2 and user.subscription_source in [nil, 0]
      )

    ~H"""
    <dialog id="getting_started" class="modal">
      <form id="onboarding-dismiss" method="dialog"></form>
      <div class="modal-box max-w-2xl bg-base-200">
        <div id="onboarding-choice-screen">
          <div class="text-center mb-6">
            <h3 class="text-2xl font-bold text-primary mb-2">{tm(@locale, "welcome_to_dawarich")}</h3>
            <p class="text-base-content/70">
              {tm(@locale, "your_map_starts_with_your_next_step_literally")}
            </p>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <button
              type="button"
              class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-primary/40 hover:border-primary sm:col-span-2"
              phx-click={show("onboarding-track-screen", "onboarding_track_selected")}
            >
              <div class="card-body p-5">
                <div class="flex items-center gap-2 mb-2">
                  <Icon.icon name="smartphone" class="w-6 h-6 text-primary" />
                  <h4 class="text-lg font-semibold">{tm(@locale, "start_tracking_now")}</h4>
                  <span class="badge badge-primary badge-sm">{tm(@locale, "minutes")}</span>
                </div>
                <p class="text-sm text-base-content/70">
                  {tm(@locale, "get_the_app_scan_a_qr_code_and_watch_your")}
                </p>
              </div>
            </button>
            <button
              type="button"
              class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-transparent hover:border-secondary"
              phx-click={show("onboarding-import-screen", "onboarding_import_selected")}
            >
              <div class="card-body p-5">
                <div class="flex items-center gap-2 mb-2">
                  <Icon.icon name="file-up" class="w-6 h-6 text-secondary" />
                  <h4 class="text-lg font-semibold">{tm(@locale, "i_have_data")}</h4>
                </div>
                <p class="text-sm text-base-content/70">
                  {tm(@locale, "import_google_takeout_gpx_kml_geojson_or_owntracks_files")}
                </p>
              </div>
            </button>
            <form method="post" action="/settings/onboarding/demo_data" class="contents">
              <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
              <button
                type="submit"
                disabled={@demo_loaded}
                phx-click={
                  JS.dispatch("dawarich:track", detail: %{event: "onboarding_demo_selected"})
                }
                class={"card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-transparent hover:border-accent #{if @demo_loaded, do: "opacity-50 pointer-events-none"}"}
              >
                <div class="card-body p-5">
                  <div class="flex items-center gap-2 mb-2">
                    <Icon.icon name="map" class="w-6 h-6 text-accent" />
                    <h4 class="text-lg font-semibold">
                      {if @demo_loaded,
                        do: t(@locale, "javascript.demo.already_loaded", %{}),
                        else: tm(@locale, "explore_with_demo_data")}
                    </h4>
                  </div>
                  <p class="text-sm text-base-content/70">
                    {tm(@locale, "load_sample_location_data_3_days_in_berlin_to_see")}
                  </p>
                </div>
              </button>
            </form>
            <a
              :if={@family_card}
              class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-transparent hover:border-info sm:col-span-2"
              href={@family_href}
            >
              <div class="card-body p-5">
                <div class="flex items-center gap-2 mb-2">
                  <Icon.icon name="users" class="w-6 h-6 text-info" />
                  <h4 class="text-lg font-semibold">{tm(@locale, "invite_your_family")}</h4>
                </div>
                <p class="text-sm text-base-content/70">
                  {tm(@locale, "add_your_family_and_see_each_other_on_the_map")}
                </p>
              </div>
            </a>
          </div>
          <div class="text-center mt-6">
            <button class="btn btn-ghost btn-sm" form="onboarding-dismiss">
              {tm(@locale, "skip_for_now")}
            </button>
          </div>
        </div>
        <div id="onboarding-import-screen" class="hidden">
          <div class="flex items-center gap-2 mb-4">
            <button
              type="button"
              class="btn btn-ghost btn-sm btn-circle"
              phx-click={show("onboarding-choice-screen")}
            >
              <Icon.icon name="arrow-left" class="w-4 h-4" />
            </button>
            <h3 class="text-xl font-bold">{tm(@locale, "import_your_data")}</h3>
          </div>
          <div class="card bg-base-100 shadow-sm mb-4">
            <div class="card-body p-4">
              <h4 class="card-title text-sm">{tm(@locale, "supported_formats")}</h4>
              <ul class="text-xs space-y-1">
                <li :for={{label, text} <- @formats}>
                  <strong>{tm(@locale, label)}</strong> {tm(@locale, text)}
                </li>
              </ul>
              <div :if={@legacy_trial} class="text-xs text-warning mt-2 font-medium">
                {tm(@locale, "trial_limitations_max_5_imports_10mb_per_file_current_imports")} {@navbar.imports.count}/5
              </div>
            </div>
          </div>
          <div class="flex justify-end">
            <a class="btn btn-primary" href="/imports/new">{tm(@locale, "import_files")}</a>
          </div>
        </div>
        <.track_screen locale={@locale} base_url={@base_url} current_user={@current_user} native />
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>{tm(@locale, "close")}</button>
      </form>
    </dialog>
    """
  end
end
