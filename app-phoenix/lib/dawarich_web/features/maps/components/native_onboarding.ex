defmodule DawarichWeb.NativeOnboarding do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.OnboardingScreens, only: [track_screen: 1, tm: 2]

  alias DawarichWeb.Icon
  alias Phoenix.LiveView.JS

  @screens ~w(native-onboarding-choice-screen native-onboarding-import-screen native-onboarding-track-screen)

  def show(screen, event \\ nil) do
    js =
      JS.hide(to: Enum.map_join(@screens -- [screen], ", ", &"##{&1}"))
      |> JS.show(to: "##{screen}")

    js =
      if screen == "native-onboarding-track-screen",
        do: JS.dispatch(js, "dawarich:reveal-qr", to: "#native-onboarding-api-qr"),
        else: js

    if event, do: JS.dispatch(js, "dawarich:track", detail: %{event: event}), else: js
  end

  def modal(assigns) do
    assigns = Map.put_new(assigns, :http, false)
    %{current_user: user, navbar: %{family: family}} = assigns

    assigns =
      assign(assigns,
        family_card: family.available or family.member,
        family_href: if(family.available, do: "/family", else: "/family/new"),
        demo_loaded: assigns.navbar.imports.demo,
        demo_loading: Map.get(assigns, :demo_status) == :loading,
        target: Map.get(assigns, :target),
        upload: Map.get(assigns, :upload),
        legacy_trial: user.status == 2 and user.subscription_source in [nil, 0],
        auto: Map.get(assigns, :auto_open, false) == true and assigns.navbar.onboarding == true
      )

    ~H"""
    <dialog
      id="getting_started"
      class="modal"
      phx-hook={@target && "Onboarding"}
      data-native-auto={@target && to_string(@auto)}
      data-native-user-id={@target && @current_user.id}
      phx-target={@target}
    >
      <form id="native-onboarding-dismiss" method="dialog"></form>
      <div class="modal-box max-w-2xl bg-base-200">
        <div id="native-onboarding-choice-screen">
          <div class="text-center mb-6">
            <h3 class="text-2xl font-bold text-primary mb-2">{tm(@locale, "welcome_to_dawarich")}</h3>
            <p class="text-base-content/70">
              {tm(@locale, "your_map_starts_with_your_next_step_literally")}
            </p>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <button
              class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-primary/40 hover:border-primary sm:col-span-2"
              phx-click={
                !@http && show("native-onboarding-track-screen", "onboarding_track_selected")
              }
              data-auth-onboarding-screen={@http && "native-onboarding-track-screen"}
              data-auth-track-event={@http && "onboarding_track_selected"}
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
              phx-click={
                !@http && show("native-onboarding-import-screen", "onboarding_import_selected")
              }
              data-auth-onboarding-screen={@http && "native-onboarding-import-screen"}
              data-auth-track-event={@http && "onboarding_import_selected"}
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
              :if={@target}
              id="native-demo-load"
              disabled={@demo_loaded or @demo_loading}
              phx-click={
                JS.dispatch("dawarich:track", detail: %{event: "onboarding_demo_selected"})
                |> JS.push("demo:load", target: @target)
              }
              class={demo_class(@demo_loaded or @demo_loading)}
            >
              <.demo_body locale={@locale} loaded={@demo_loaded} loading={@demo_loading} />
            </button>
            <form
              :if={!@target}
              data-auth-form={@http}
              data-auth-track-event={@http && "onboarding_demo_selected"}
              method="post"
              action="/settings/onboarding/demo_data"
              class="contents"
            >
              <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
              <button
                type="submit"
                disabled={@demo_loaded}
                phx-click={
                  !@http &&
                    JS.dispatch("dawarich:track", detail: %{event: "onboarding_demo_selected"})
                }
                class={demo_class(@demo_loaded)}
              >
                <.demo_body locale={@locale} loaded={@demo_loaded} loading={false} />
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
            <button class="btn btn-ghost btn-sm" form="native-onboarding-dismiss">
              {tm(@locale, "skip_for_now")}
            </button>
          </div>
        </div>
        <DawarichWeb.OnboardingImport.screen
          locale={@locale}
          http={@http}
          legacy_trial={@legacy_trial}
          imports={@navbar.imports.count}
          upload={@upload}
        />
        <.track_screen
          locale={@locale}
          base_url={@base_url}
          current_user={@current_user}
          native
          http={@http}
        />
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>{tm(@locale, "close")}</button>
      </form>
    </dialog>
    """
  end

  defp demo_class(inactive),
    do:
      "card bg-base-100 shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left border-2 border-transparent hover:border-accent" <>
        if(inactive, do: " opacity-50 pointer-events-none", else: "")

  attr :locale, :string, required: true
  attr :loaded, :boolean, required: true
  attr :loading, :boolean, required: true

  defp demo_body(assigns) do
    ~H"""
    <div class="card-body p-5">
      <div class="flex items-center gap-2 mb-2">
        <span :if={@loading} class="loading loading-spinner loading-md text-accent"></span>
        <Icon.icon :if={!@loading} name="map" class="w-6 h-6 text-accent" />
        <h4 class="text-lg font-semibold">
          {cond do
            @loading -> t(@locale, "javascript.demo.creating", %{})
            @loaded -> t(@locale, "javascript.demo.already_loaded", %{})
            true -> tm(@locale, "explore_with_demo_data")
          end}
        </h4>
      </div>
      <p class="text-sm text-base-content/70">
        {if @loading,
          do: t(@locale, "javascript.demo.creating_help", %{}),
          else: tm(@locale, "load_sample_location_data_3_days_in_berlin_to_see")}
      </p>
    </div>
    """
  end
end
