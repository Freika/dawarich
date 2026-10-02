defmodule DawarichWeb.OnboardingModal do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.OnboardingScreens, only: [import_screen: 1, track_screen: 1, tm: 2]

  alias DawarichWeb.Icon

  attr :current_user, :map, required: true
  attr :navbar, :map, required: true
  attr :locale, :string, required: true
  attr :base_url, :string, required: true
  attr :rails_csrf_token, :string, default: nil
  attr :auto_open, :boolean, default: false

  def onboarding_modal(assigns) do
    %{current_user: user, navbar: %{family: family}} = assigns

    assigns =
      assign(assigns,
        trial: user.status == 2,
        legacy_trial: user.status == 2 and user.subscription_source in [nil, 0],
        family_card: family.available or family.member,
        family_href: if(family.available, do: "/family", else: "/family/new"),
        upload_url: assigns.base_url <> "/imports/direct_uploads"
      )

    ~H"""
    <div
      id="onboarding-modal"
      phx-hook="RailsStimulus"
      phx-update="ignore"
      data-controller="onboarding-modal"
      data-onboarding-modal-auto-value={to_string(@auto_open)}
      data-onboarding-modal-showable-value={to_string(@navbar.onboarding)}
      data-onboarding-modal-onboarding-url-value="/settings/onboarding"
      data-onboarding-modal-user-trial-value={to_string(@trial)}
      data-onboarding-modal-imports-count-value={@navbar.imports.count}
      data-onboarding-modal-demo-data-url-value="/settings/onboarding/demo_data"
      data-onboarding-modal-has-demo-data-value={to_string(@navbar.imports.demo)}
      data-onboarding-modal-user-id-value={@current_user.id}
    >
      <dialog id="getting_started" class="modal" data-onboarding-modal-target="modal">
        <div class="modal-box max-w-2xl bg-base-200">
          <div data-onboarding-modal-target="choiceScreen">
            <div class="text-center mb-6">
              <h3 class="text-2xl font-bold text-primary mb-2">
                {tm(@locale, "welcome_to_dawarich")}
              </h3>
              <p class="text-base-content/70">
                {tm(@locale, "your_map_starts_with_your_next_step_literally")}
              </p>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <button
                class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-primary/40 hover:border-primary sm:col-span-2"
                data-action="onboarding-modal#showTrack"
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
                class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-transparent hover:border-secondary"
                data-action="onboarding-modal#showImport"
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
              <button
                class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-transparent hover:border-accent"
                data-action="onboarding-modal#loadDemoData"
                data-onboarding-modal-target="demoButton"
              >
                <div class="card-body p-5">
                  <div class="flex items-center gap-2 mb-2">
                    <Icon.icon name="map" class="w-6 h-6 text-accent" />
                    <h4 class="text-lg font-semibold">{tm(@locale, "explore_with_demo_data")}</h4>
                  </div>
                  <p class="text-sm text-base-content/70">
                    {tm(@locale, "load_sample_location_data_3_days_in_berlin_to_see")}
                  </p>
                </div>
              </button>
              <a
                :if={@family_card}
                class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-transparent hover:border-info sm:col-span-2"
                data-action="onboarding-modal#dismiss"
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
              <button class="btn btn-ghost btn-sm" data-action="onboarding-modal#dismiss">
                {tm(@locale, "skip_for_now")}
              </button>
            </div>
          </div>
          <.import_screen
            locale={@locale}
            imports={@navbar.imports.count}
            legacy_trial={@legacy_trial}
            upload_url={@upload_url}
            rails_csrf_token={@rails_csrf_token}
          />
          <.track_screen locale={@locale} base_url={@base_url} current_user={@current_user} />
        </div>
        <form method="dialog" class="modal-backdrop">
          <button>{tm(@locale, "close")}</button>
        </form>
      </dialog>
    </div>
    """
  end
end
