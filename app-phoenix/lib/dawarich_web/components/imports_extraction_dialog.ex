defmodule DawarichWeb.ImportsExtractionDialog do
  @moduledoc false
  use Phoenix.Component

  alias DawarichWeb.Translate

  attr :id, :integer, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true

  def dialog(assigns) do
    ~H"""
    <dialog id={"extraction-dialog-#{@id}"} class="modal">
      <div class="modal-box max-w-xl">
        <h3 class="font-bold text-lg">{text(@locale, "extract_additional_data_from_this_import")}</h3>
        <div class="prose prose-sm mt-4 text-base-content/80">
          <p>{text(@locale, "dawarich_originally_imported_your_file_as_raw_gps_points_the")}</p>
          <ul>
            <li>
              <strong>{text(@locale, "visits")}</strong> {text(
                @locale,
                "places_where_the_source_app_recorded_you_spending_time_with"
              )}
            </li>
            <li>
              <strong>{text(@locale, "tracks")}</strong> {text(
                @locale,
                "journeys_identified_between_those_visits_with_their_classified_transport"
              )}
            </li>
            <li>
              <strong>{text(@locale, "places")}</strong> {text(
                @locale,
                "the_named_places_home_work_frequent_restaurants_the_source_app"
              )}
            </li>
          </ul>
          <p>{Phoenix.HTML.raw(text(@locale, "extract_to_add_html"))}</p>
        </div>
        <form
          data-turbo-frame={"import-#{@id}-extraction"}
          action={"/imports/#{@id}/extraction"}
          accept-charset="UTF-8"
          method="post"
        >
          <input type="hidden" name="authenticity_token" value={@csrf} />
          <div class="form-control mt-4">
            <label class="label cursor-pointer justify-start gap-3">
              <input name="trust_source" type="hidden" value="false" /><input
                class="checkbox checkbox-primary"
                type="checkbox"
                value="true"
                checked="checked"
                name="trust_source"
                id="trust_source"
              />
              <div>
                <div class="label-text font-medium">
                  {text(@locale, "trust_the_source_app_s_classification")}
                </div>
                <div class="label-text-alt text-base-content/60">
                  {text(
                    @locale,
                    "when_checked_transportation_modes_driving_walking_cycling_transit_the_so"
                  )}
                </div>
              </div>
            </label>
          </div>
          <div class="modal-action">
            <button
              type="button"
              class="btn btn-ghost"
              data-action="click->import-extraction#close"
              data-import-extraction-dialog-id-param={"extraction-dialog-#{@id}"}
            >
              {text(@locale, "cancel")}
            </button>
            <input
              type="submit"
              name="commit"
              value={text(@locale, "extract")}
              class="btn btn-primary"
              data-disable-with={text(@locale, "extract")}
            />
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop"><button>{text(@locale, "close")}</button></form>
    </dialog>
    """
  end

  defp text(locale, key), do: Translate.t(locale, "imports.extraction_dialog." <> key, %{})
end
