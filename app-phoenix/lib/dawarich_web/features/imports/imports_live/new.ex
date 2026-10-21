defmodule DawarichWeb.ImportsLive.New do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]

  @formats [
    {"google_maps", "records_json_semantic_history_phone_takeout_json"},
    {"google_photos", "takeout_metadata_sidecars_json"},
    {"mobile_photo_library", "dawarich_mobile_app_export_json"},
    {"gpx", "track_files_gpx"},
    {"geojson", "feature_collections_json_geojson"},
    {"owntracks", "recorder_files_rec"},
    {"kml", "kml_files_kml_kmz"},
    {"fit", "garmin_activity_files_fit"},
    {"tcx", "training_center_files_tcx"},
    {"csv", "location_data_csv"},
    {"polarsteps", "locations_json_json"},
    {"zip", "archives_containing_any_of_the_above_zip"}
  ]
  @accept ".json,.geojson,.gpx,.kml,.kmz,.tcx,.fit,.csv,.rec,.zip,application/json,application/geo+json,application/gpx+xml,application/vnd.google-earth.kml+xml,application/vnd.google-earth.kmz,application/zip"
  @splitter "https://dawarich.app/tools/google-timeline-splitter?utm_source=dawarich&utm_medium=import_page&utm_campaign=trial_banner"

  @impl true
  def mount(_, _, socket) do
    case Dawarich.Imports.upload_page(socket.assigns.current_scope) do
      {:ok, page} ->
        socket =
          socket
          |> assign(page)
          |> assign(
            page_title: t(socket.assigns.locale, "imports.new.new_import_2", %{}),
            formats: @formats,
            accept: @accept,
            splitter: @splitter
          )

        {:ok, DawarichWeb.ImportsUpload.configure(socket)}

      _ ->
        {:ok, redirect(socket, to: "/imports")}
    end
  end

  @impl true
  def handle_event(event, params, socket),
    do: DawarichWeb.ImportsUpload.event(event, params, socket)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto md:w-2/3 w-full my-5" data-testid="native-imports-root">
      <.page_header title={t(@locale, "imports.new.new_import", %{})}>
        <a class="btn btn-sm" href="/imports">
          <.icon name="arrow-left" class="w-4 h-4" /> {t(@locale, "imports.new.back_to_imports", %{})}
        </a>
      </.page_header>
      <div :if={@trial} class="alert alert-info my-4">
        <.icon name="scissors" class="w-5 h-5 shrink-0" />
        <span>
          {t(@locale, "imports.new.google_timeline_file_too_large", %{})}
          <a target="_blank" rel="noopener" class="link link-primary font-semibold" href={@splitter}>{t(
            @locale,
            "imports.new.split_it_with_our_free_private_tool",
            %{}
          )}</a> {t(@locale, "imports.new.your_data_never_leaves_your_browser", %{})}
        </span>
      </div>
      <div class="card bg-base-200 w-full max-w-md mb-5 mt-5">
        <div class="card-body p-4">
          <h3 class="card-title text-sm">
            {t(@locale, "imports.form.supported_import_formats", %{})}
          </h3>
          <ul class="text-xs space-y-1.5">
            <li :for={{name, files} <- @formats} class="flex items-center gap-1.5">
              <.icon name="circle-check" class="w-3.5 h-3.5 text-success shrink-0" />
              <strong>{t(@locale, "imports.form." <> name, %{})}</strong> {t(
                @locale,
                "imports.form." <> files,
                %{}
              )}
            </li>
          </ul>
          <div class="text-xs text-base-content/50 mt-2">
            {t(@locale, "imports.form.file_format_is_automatically_detected_during_upload", %{})}
          </div>
          <div class="flex items-start gap-2 text-xs text-info mt-2">
            <.icon name="info" class="w-3.5 h-3.5 shrink-0 mt-0.5" />
            <span>{t(
              @locale,
              "imports.form.for_files_larger_than_200mb_consider_compressing_them_into_a",
              %{}
            )}</span>
          </div>
          <div :if={@trial} class="text-xs text-warning mt-2 font-medium">
            {t(@locale, "imports.form.trial_limitations_max_5_imports_10mb_per_file", %{})}
            <br /> {t(@locale, "imports.form.current_imports", %{})} {@imports_count}/5
          </div>
        </div>
      </div>
      <DawarichWeb.ImportsUpload.form
        upload={@uploads[@upload_name]}
        locale={@locale}
        accept={@accept}
        limits={@upload_limits}
        error={@upload_error}
        fallback={@upload_fallback}
      />
    </div>
    """
  end
end
