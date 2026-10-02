defmodule DawarichWeb.ImportsExtractionCard do
  @moduledoc false
  use Phoenix.Component
  alias Dawarich.Imports.Postprocessing.Policy
  alias DawarichWeb.Translate
  @statuses ~w(not_attempted pending running completed failed unsupported)
  attr :record, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :context, :map, required: true

  def card(assigns) do
    record = assigns.record
    supported = record.source in [0, 3, 4, 13]
    eligible = Policy.extracts?(%{record | additional_data_extraction_status: 0})

    data =
      if is_map(record.additional_data_extraction),
        do: record.additional_data_extraction,
        else: %{}

    counts = if is_map(data["counts"]), do: data["counts"], else: %{}
    in_flight = record.additional_data_extraction_status in [1, 2]

    stalled =
      in_flight and Policy.tracks?(%{record | additional_data_extraction: data}, assigns.context)

    recover = not in_flight or stalled

    label =
      cond do
        stalled -> "start_over"
        record.additional_data_extraction_status == 3 -> "re_extract"
        record.additional_data_extraction_status == 4 -> "retry_extraction"
        true -> "extract_additional_data"
      end

    assigns =
      assign(assigns,
        eligible: eligible,
        supported: supported,
        counts: counts,
        in_flight: in_flight,
        stalled: stalled,
        recover: recover,
        label: label,
        error: data["error_message"],
        status: Enum.at(@statuses, record.additional_data_extraction_status, "not_attempted")
      )

    ~H"""
    <div data-testid="import-extraction-card" class="card bg-base-200 my-5">
      <div class="card-body">
        <h3 class="card-title">
          {text(@locale, "additional_data")}
          <span class="badge badge-sm">{Translate.t(
            @locale,
            "helpers.imports.extraction_status." <> @status,
            %{}
          )}</span>
        </h3>
        <p :if={@record.source == 4 and not @eligible}>
          {text(@locale, "this_gpx_file_holds_no_waypoints")}
        </p>
        <p :if={not @supported}>
          {text(@locale, "this_import_format_doesn_t_carry_visits_named_places_or")}
        </p>
        <%= if @eligible do %>
          <p :if={@record.additional_data_extraction_status == 3}>
            {text(@locale, "extracted")}
            <span :for={
              {key, label} <- [
                {"visits", "visits"},
                {"places", "places"},
                {"tracks", "tracks"},
                {"segments", "transportation_mode_segments"}
              ]
            }>
              <strong data-extraction-count={key}>{Map.get(@counts, key, 0)}</strong> {text(
                @locale,
                label
              )}
            </span>
          </p>
          <p :if={@record.additional_data_extraction_status == 4} class="text-error">
            {text(@locale, "extraction_failed")} {@error}
          </p>
          <p :if={@in_flight and not @stalled}>
            {text(
              @locale,
              if(@record.additional_data_extraction_status == 2, do: "extracting", else: "queued")
            )}
          </p>
          <p :if={@stalled} class="text-warning">
            {text(@locale, "this_extraction_stopped_responding_it_s_safe_to_start_it")}
          </p>
          <p :if={@record.additional_data_extraction_status in [0, 5]}>
            {text(@locale, "dawarich_originally_imported_your_file_as_raw_gps_points_click")}
          </p>
          <form
            :if={@recover and @record.status != 4}
            action={"/imports/#{@record.id}/extraction"}
            method="post"
            data-turbo="false"
          >
            <input type="hidden" name="authenticity_token" value={@csrf} />
            <input type="hidden" name="trust_source" value="false" />
            <label class="flex gap-2 items-center my-3"><input
              type="checkbox"
              name="trust_source"
              value="true"
              checked
              class="checkbox"
            />{Translate.t(
              @locale,
              "imports.extraction_dialog.trust_the_source_app_s_classification",
              %{}
            )}</label>
            <button data-testid="import-extraction-submit" class="btn btn-primary">{text(
              @locale,
              @label
            )}</button>
          </form>
          <form
            :if={@recover and @record.status != 4 and @record.additional_data_extraction_status != 0}
            action={"/imports/#{@record.id}/extraction"}
            method="post"
            data-turbo="false"
            class="mt-3"
          >
            <input type="hidden" name="authenticity_token" value={@csrf} /><input
              type="hidden"
              name="_method"
              value="delete"
            />
            <button
              data-testid="import-extraction-remove"
              class="btn btn-ghost text-error"
              data-confirm={
                text(@locale, "remove_the_visits_places_and_tracks_this_extraction_created_your")
              }
            >{text(@locale, "remove_extracted_data")}</button>
          </form>
        <% end %>
      </div>
    </div>
    """
  end

  defp text(locale, key), do: Translate.t(locale, "imports.extraction_card." <> key, %{})
end
