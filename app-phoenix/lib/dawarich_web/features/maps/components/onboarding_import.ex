defmodule DawarichWeb.OnboardingImport do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.OnboardingScreens, only: [tm: 2]
  alias DawarichWeb.Icon

  @formats [
    {"google_maps", "records_json_semantic_history_phone_takeout_json"},
    {"gpx", "track_files_gpx"},
    {"geojson", "feature_collections_json"},
    {"owntracks", "recorder_files_rec"},
    {"kml", "kml_files_kml_kmz"}
  ]

  def screen(assigns) do
    assigns = assign(assigns, formats: @formats)

    ~H"""
    <div id="native-onboarding-import-screen" class="hidden">
      <div class="flex items-center gap-2 mb-4">
        <button
          class="btn btn-ghost btn-sm btn-circle"
          phx-click={!@http && DawarichWeb.NativeOnboarding.show("native-onboarding-choice-screen")}
          data-auth-onboarding-screen={@http && "native-onboarding-choice-screen"}
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
          <div class="text-xs text-base-content/60 mt-2">
            {tm(@locale, "file_format_is_automatically_detected_during_upload")}
          </div>
          <div :if={@legacy_trial} class="text-xs text-warning mt-2 font-medium">
            {tm(@locale, "trial_limitations_max_5_imports_10mb_per_file_current_imports")} {@imports}/5
          </div>
        </div>
      </div>
      <DawarichWeb.ImportsUpload.form
        :if={@upload}
        {Map.merge(@upload, %{locale: @locale, variant: :onboarding})}
      />
      <div :if={!@upload} class="flex justify-end">
        <a class="btn btn-primary" href="/imports/new">{tm(@locale, "import_files")}</a>
      </div>
    </div>
    """
  end
end
