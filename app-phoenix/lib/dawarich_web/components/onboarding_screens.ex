defmodule DawarichWeb.OnboardingScreens do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.{Assets, Icon}

  @formats [
    {"google_maps", "records_json_semantic_history_phone_takeout_json"},
    {"gpx", "track_files_gpx"},
    {"geojson", "feature_collections_json"},
    {"owntracks", "recorder_files_rec"},
    {"kml", "kml_files_kml_kmz"}
  ]

  def tm(locale, key), do: t(locale, "map.onboarding_modal." <> key, %{})

  attr :locale, :string, required: true
  attr :imports, :integer, required: true
  attr :legacy_trial, :boolean, required: true
  attr :upload_url, :string, required: true
  attr :rails_csrf_token, :string, default: nil

  def import_screen(assigns) do
    assigns = assign(assigns, :formats, @formats)

    ~H"""
    <div data-onboarding-modal-target="importScreen" class="hidden">
      <div class="flex items-center gap-2 mb-4">
        <button class="btn btn-ghost btn-sm btn-circle" data-action="onboarding-modal#showChoice">
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
          <div class="text-xs text-base-content/60 mt-2">
            {tm(@locale, "file_format_is_automatically_detected_during_upload")}
          </div>
          <div :if={@legacy_trial} class="text-xs text-warning mt-2 font-medium">
            {tm(@locale, "trial_limitations_max_5_imports_10mb_per_file_current_imports")} {@imports}/5
          </div>
        </div>
      </div>
      <form
        class="contents"
        data-controller="upload"
        data-upload-url-value={@upload_url}
        data-upload-field-name-value="import[files][]"
        data-upload-multiple-value="true"
        data-upload-user-trial-value={to_string(@legacy_trial)}
        data-upload-max-imports-value="5"
        data-upload-current-imports-count-value={@imports}
        data-upload-preserve-original-filename-value="true"
        data-upload-target="form"
        enctype="multipart/form-data"
        action="/imports"
        accept-charset="UTF-8"
        method="post"
      >
        <input
          :if={@rails_csrf_token}
          type="hidden"
          name="authenticity_token"
          value={@rails_csrf_token}
        />
        <label class="form-control w-full mb-4">
          <div class="label">
            <span class="label-text">{tm(@locale, "select_one_or_multiple_files")}</span>
          </div>
          <input name="import[files][]" type="hidden" value="" /><input
            multiple="multiple"
            name="import[files][]"
            class="file-input file-input-bordered w-full"
            data-upload-target="input"
            data-direct-upload-url={@upload_url}
            type="file"
            id="files"
          />
          <div class="text-xs text-base-content/60 mt-2">
            {tm(@locale, "files_will_be_uploaded_directly_to_storage_please_be_patient")}
          </div>
        </label>
        <div class="flex justify-end">
          <input
            type="submit"
            name="commit"
            value={tm(@locale, "import_files")}
            class="btn btn-primary"
            data-upload-target="submit"
            data-disable-with={tm(@locale, "import_files")}
          />
        </div>
      </form>
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :base_url, :string, required: true
  attr :current_user, :map, required: true
  attr :native, :boolean, default: false

  def track_screen(assigns) do
    ~H"""
    <div
      data-onboarding-modal-target={!@native && "trackScreen"}
      id={@native && "onboarding-track-screen"}
      class="hidden"
    >
      <div class="flex items-center gap-2 mb-4">
        <button
          class="btn btn-ghost btn-sm btn-circle"
          data-action={!@native && "onboarding-modal#showChoice"}
          phx-click={@native && DawarichWeb.NativeOnboarding.show("onboarding-choice-screen")}
        >
          <Icon.icon name="arrow-left" class="w-4 h-4" />
        </button>
        <h3 class="text-xl font-bold">{tm(@locale, "start_tracking")}</h3>
      </div>
      <div class="card bg-base-100 shadow-sm">
        <div class="card-body p-4 space-y-4">
          <div>
            <div class="flex items-center gap-2 mb-2">
              <div class="badge badge-primary badge-sm">1</div>
              <h4 class="font-semibold">{tm(@locale, "download_the_app")}</h4>
            </div>
            <div class="flex justify-center items-center gap-3 flex-wrap">
              <a
                class="inline-block rounded-lg border-2 border-transparent hover:border-primary hover:shadow-lg hover:shadow-primary/20 transition-all duration-300 ease-in-out transform hover:scale-105"
                href="https://apps.apple.com/de/app/dawarich/id6739544999?itscg=30200&amp;itsct=apps_box_badge&amp;mttnsubad=6739544999"
              >
                <img
                  class="h-[40px] transition-opacity duration-300"
                  src={
                    Assets.stylesheet_path("Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg")
                  }
                />
              </a>
              <a
                class="inline-block rounded-lg border-2 border-transparent hover:border-primary hover:shadow-lg hover:shadow-primary/20 transition-all duration-300 ease-in-out transform hover:scale-105"
                target="_blank"
                rel="noopener"
                href="https://play.google.com/store/apps/details?id=app.dawarich.Dawarich"
              >
                <img
                  class="h-[40px] transition-opacity duration-300"
                  src={Assets.stylesheet_path("GetItOnGooglePlay_Badge_Web_color_English.svg")}
                />
              </a>
            </div>
          </div>
          <div>
            <div class="flex items-center gap-2 mb-2">
              <div class="badge badge-primary badge-sm">2</div>
              <h4 class="font-semibold">{tm(@locale, "scan_qr_code_to_connect")}</h4>
            </div>
            <p class="text-sm text-base-content/70 mb-3">
              {tm(@locale, "scan_this_qr_code_with_the_dawarich_app_to_automatically")}
            </p>
            <div class="flex justify-center">
              <div class="bg-white p-3 rounded-lg shadow-inner">
                {Phoenix.HTML.raw(Dawarich.QrSvg.api_key(@base_url <> "/", @current_user.api_key, 3))}
              </div>
            </div>
          </div>
          <div class="divider text-xs">{tm(@locale, "or")}</div>
          <p class="text-sm text-base-content/70">
            {tm(@locale, "grab_your_api_key_from")}
            <a class="link link-primary font-medium" href="/settings/general">{tm(@locale, "settings")}</a>
            {tm(@locale, "and_follow_the")}
            <a
              class="link link-primary font-medium"
              target="_blank"
              rel="noopener"
              href="https://dawarich.app/docs/tutorials/track-your-location?utm_source=app&amp;utm_medium=referral&amp;utm_campaign=onboarding"
            >{tm(@locale, "setup_guide")}</a>.
          </p>
          <p class="text-xs text-base-content/60">
            {tm(@locale, "have_old_location_history_like_a_google_takeout_tracking_works")}
            <button
              type="button"
              class="link link-primary"
              data-action={!@native && "onboarding-modal#showImport"}
              phx-click={
                @native &&
                  DawarichWeb.NativeOnboarding.show(
                    "onboarding-import-screen",
                    "onboarding_import_selected"
                  )
              }
            >{tm(@locale, "import_your_history_anytime")}</button>.
          </p>
        </div>
      </div>
      <div class="flex justify-end mt-4">
        <button
          class="btn btn-primary"
          data-action={!@native && "onboarding-modal#dismiss"}
          form={@native && "onboarding-dismiss"}
        >
          {tm(@locale, "got_it_let_s_start")}
        </button>
      </div>
    </div>
    """
  end
end
