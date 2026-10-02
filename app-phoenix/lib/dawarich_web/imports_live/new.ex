defmodule DawarichWeb.ImportsLive.New do
  @moduledoc false
  use DawarichWeb, :live_view
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
         trial: user.status == 2 and user.subscription_source in [nil, 0]
       )}
    else
      {:ok, redirect(socket, to: "/imports")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div data-testid="native-imports-root" class="mx-auto md:w-2/3 w-full my-5">
      <h1 class="font-bold text-3xl">{t(@locale, "imports.new.new_import", %{})}</h1>
      <a href="/imports" class="btn btn-sm my-4">{t(@locale, "imports.new.back_to_imports", %{})}</a>
      <div class="card bg-base-200 max-w-md my-5">
        <div class="card-body p-4">
          <h3 class="card-title text-sm">
            {t(@locale, "imports.form.supported_import_formats", %{})}
          </h3>
          <p class="text-sm">
            GPX, GeoJSON, Google Maps, Google Photos, OwnTracks, KML/KMZ, TCX, FIT, CSV, Polarsteps, ZIP
          </p>
          <p class="text-xs">
            {t(@locale, "imports.form.file_format_is_automatically_detected_during_upload", %{})}
          </p>
          <p :if={@trial} class="text-xs text-warning">
            {t(@locale, "imports.form.trial_limitations_max_5_imports_10mb_per_file", %{})}<br />{t(
              @locale,
              "imports.form.current_imports",
              %{}
            )} {@imports_count}/5
          </p>
        </div>
      </div>
      <form
        id="native-import-upload"
        action="/imports"
        method="post"
        data-turbo="false"
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
      >
        <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
        <label class="form-control max-w-md my-5">
          <span class="label-text">{t(@locale, "imports.form.select_one_or_multiple_files", %{})}</span>
          <input
            data-testid="import-file-input"
            type="file"
            name="import[files][]"
            multiple
            accept=".json,.geojson,.gpx,.kml,.kmz,.tcx,.fit,.csv,.rec,.zip"
            class="file-input file-input-bordered"
            data-upload-target="input"
          />
          <span class="text-sm mt-2">{t(
            @locale,
            "imports.form.files_will_be_uploaded_directly_to_storage_please_be_patient",
            %{}
          )}</span>
        </label>
        <div data-testid="import-upload-progress">
          <button
            type="submit"
            data-testid="import-submit"
            data-upload-target="submit"
            class="btn btn-primary"
            disabled
          >{t(@locale, "imports.new.new_import", %{})}</button>
        </div>
      </form>
    </div>
    """
  end
end
