defmodule DawarichWeb.ImportsExtractionDialog do
  @moduledoc false
  use Phoenix.Component

  alias DawarichWeb.Translate
  alias Phoenix.LiveView.JS

  attr :id, :integer, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :native, :boolean, default: false

  def dialog(assigns) do
    ~H"""
    <dialog
      id={"extraction-dialog-#{@id}"}
      class="modal"
      aria-labelledby={@native && "extraction-title-#{@id}"}
      phx-update={if(!@native, do: "ignore")}
    >
      <div class="modal-box max-w-xl min-w-0 [overflow-wrap:anywhere]">
        <h3 id={@native && "extraction-title-#{@id}"} class="font-bold text-lg">
          {text(@locale, "extract_additional_data_from_this_import")}
        </h3>
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
          data-turbo-frame={!@native && "import-#{@id}-extraction"}
          phx-submit={@native && "extract_import"}
          action={!@native && "/imports/#{@id}/extraction"}
          accept-charset="UTF-8"
          method="post"
        >
          <input :if={!@native} type="hidden" name="authenticity_token" value={@csrf} />
          <div class="form-control mt-4">
            <label class="label cursor-pointer justify-start gap-3 min-w-0">
              <input name="trust_source" type="hidden" value="false" /><input
                class="checkbox checkbox-primary"
                type="checkbox"
                value="true"
                checked="checked"
                name="trust_source"
                id="trust_source"
              />
              <div>
                <div class="label-text font-medium whitespace-normal">
                  {text(@locale, "trust_the_source_app_s_classification")}
                </div>
                <div class="label-text-alt text-base-content/60 whitespace-normal">
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
              data-action={!@native && "click->import-extraction#close"}
              phx-click={
                @native && JS.dispatch("dawarich:close-dialog", to: "#extraction-dialog-#{@id}")
              }
              data-import-extraction-dialog-id-param={!@native && "extraction-dialog-#{@id}"}
            >
              {text(@locale, "cancel")}
            </button>
            <input
              type="submit"
              name="commit"
              value={text(@locale, "extract")}
              class="btn btn-primary"
              data-disable-with={!@native && text(@locale, "extract")}
              phx-disable-with={@native && text(@locale, "extract")}
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
