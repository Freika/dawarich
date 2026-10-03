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
    user = socket.assigns.current_user

    if Dawarich.Entitlements.future?(user.active_until, DateTime.utc_now()) and
         (socket.assigns.self_hosted or (user.points_count || 0) < 10_000_000) do
      [[count]] =
        DawarichWeb.ImportsContext.repo().query!(
          "SELECT count(*) FROM public.imports WHERE user_id=$1",
          [user.id],
          log: false
        ).rows

      {:ok,
       assign(socket,
         page_title: t(socket.assigns.locale, "imports.new.new_import_2", %{}),
         imports_count: count,
         trial: user.status == 2 and user.subscription_source in [nil, 0],
         formats: @formats,
         accept: @accept,
         splitter: @splitter
       )}
    else
      {:ok, redirect(socket, to: "/imports")}
    end
  end

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
      <form
        id="phx-import-upload"
        class="contents"
        phx-hook="RailsStimulus"
        phx-update="ignore"
        data-controller="upload"
        data-upload-url-value={@base_url <> "/rails/active_storage/direct_uploads"}
        data-upload-field-name-value="import[files][]"
        data-upload-multiple-value="true"
        data-upload-user-trial-value={to_string(@trial)}
        data-upload-max-imports-value="5"
        data-upload-current-imports-count-value={@imports_count}
        data-upload-preserve-original-filename-value="true"
        data-upload-target="form"
        enctype="multipart/form-data"
        action="/imports"
        accept-charset="UTF-8"
        method="post"
      >
        <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
        <label class="form-control w-full max-w-xs my-5">
          <div class="label">
            <span class="label-text">{t(@locale, "imports.form.select_one_or_multiple_files", %{})}</span>
          </div>
          <input name="import[files][]" type="hidden" value="" /><input
            multiple="multiple"
            accept={@accept}
            class="file-input file-input-bordered w-full max-w-xs"
            data-upload-target="input"
            data-direct-upload-url={@base_url <> "/rails/active_storage/direct_uploads"}
            data-testid="import-file-input"
            type="file"
            name="import[files][]"
            id="import_files"
          />
          <div class="text-sm text-gray-500 mt-2">
            {t(
              @locale,
              "imports.form.files_will_be_uploaded_directly_to_storage_please_be_patient",
              %{}
            )}
          </div>
        </label>
        <div class="inline">
          <input
            type="submit"
            name="commit"
            value={submit(@locale)}
            class="rounded-lg py-3 px-5 bg-blue-600 text-white inline-block font-medium cursor-pointer"
            data-upload-target="submit"
            data-disable-with={submit(@locale)}
            data-testid="import-submit"
          />
        </div>
      </form>
    </div>
    """
  end

  defp submit(locale), do: t(locale, "helpers.submit.create", %{"model" => "Import"})
end
