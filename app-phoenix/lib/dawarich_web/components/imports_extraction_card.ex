defmodule DawarichWeb.ImportsExtractionCard do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Icon, only: [icon: 1]

  alias DawarichWeb.Translate

  @statuses ~w(not_attempted pending running completed failed unsupported)
  @badges %{
    "not_attempted" => {"badge-ghost", false},
    "pending" => {"badge-info", false},
    "running" => {"badge-info gap-1", true},
    "completed" => {"badge-success", false},
    "failed" => {"badge-error", false},
    "unsupported" => {"badge-ghost", false}
  }
  @element_keys ~w(waypoints_seen trackpoints_seen route_points_seen)
  @stale_after_seconds 6 * 3600

  attr :record, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :now, :any, required: true

  def card(assigns) do
    record = assigns.record

    data =
      if is_map(record.additional_data_extraction),
        do: record.additional_data_extraction,
        else: %{}

    status = Enum.at(@statuses, record.additional_data_extraction_status, "not_attempted")
    resolved = if status == "unsupported", do: "not_attempted", else: status
    {badge, spinner} = @badges[resolved]

    assigns =
      assign(assigns,
        id: record.id,
        status: status,
        badge: badge,
        spinner: spinner,
        label: resolved,
        no_waypoints: no_waypoints?(record.raw_data),
        stalled: status in ["pending", "running"] and stalled?(data["started_at"], assigns.now),
        counts: if(is_map(data["counts"]), do: data["counts"], else: %{}),
        error: data["error_message"]
      )

    ~H"""
    <turbo-frame
      data-controller="import-extraction"
      id={"import-#{@id}-extraction"}
      phx-hook="RailsStimulus"
    >
      <div class="card bg-base-200 mt-6 max-w-2xl">
        <div class="card-body">
          <div class="flex items-center gap-2 mb-2">
            <.icon name="layer" class="w-5 h-5 text-base-content/60" />
            <h3 class="text-lg font-semibold">{text(@locale, "additional_data")}</h3>
            <span class={"badge badge-sm " <> @badge}><span
              :if={@spinner}
              class="loading loading-dots loading-xs shrink-0"
            ></span>{Translate.t(@locale, "helpers.imports.extraction_status." <> @label, %{})}</span>
          </div>
          <%= cond do %>
            <% @no_waypoints -> %>
              <p class="text-sm text-base-content/70">
                {text(@locale, "this_gpx_file_holds_no_waypoints")}
              </p>
            <% @status == "completed" -> %>
              <p class="text-sm text-base-content/70 mb-4">
                {text(@locale, "extracted")}
                <strong>{@counts["visits"] || 0}</strong> {text(@locale, "visits")}
                <strong>{@counts["places"] || 0}</strong> {text(@locale, "places")}
                <strong>{@counts["tracks"] || 0}</strong> {text(@locale, "tracks")}
                <strong>{@counts["segments"] || 0}</strong> {text(
                  @locale,
                  "transportation_mode_segments"
                )}
              </p>
              <div class="flex flex-wrap gap-2">
                <.open_button
                  id={@id}
                  class="btn btn-sm btn-outline"
                  label={text(@locale, "re_extract")}
                />
                <.remove_button id={@id} locale={@locale} csrf={@csrf} />
              </div>
            <% @status in ["pending", "running"] and @stalled -> %>
              <p class="text-sm text-warning mb-2">
                {text(@locale, "this_extraction_stopped_responding_it_s_safe_to_start_it")}
              </p>
              <div class="flex flex-wrap gap-2">
                <.open_button
                  id={@id}
                  class="btn btn-sm btn-outline"
                  label={text(@locale, "start_over")}
                />
                <.remove_button id={@id} locale={@locale} csrf={@csrf} />
              </div>
            <% @status in ["pending", "running"] -> %>
              <p class="text-sm text-base-content/70 flex items-center gap-2">
                <span class="loading loading-dots loading-sm shrink-0"></span>
                {text(@locale, if(@status == "running", do: "extracting", else: "queued"))}
              </p>
            <% @status == "failed" -> %>
              <p class="text-sm text-error mb-2">
                {text(@locale, "extraction_failed")} {@error}
              </p>
              <div class="flex flex-wrap gap-2">
                <.open_button
                  id={@id}
                  class="btn btn-sm btn-outline"
                  label={text(@locale, "retry_extraction")}
                />
                <.remove_button id={@id} locale={@locale} csrf={@csrf} />
              </div>
            <% true -> %>
              <p class="text-sm text-base-content/70 mb-4">
                {text(@locale, "dawarich_originally_imported_your_file_as_raw_gps_points_click")}
              </p>
              <.open_button
                id={@id}
                class="btn btn-sm btn-primary"
                label={text(@locale, "extract_additional_data")}
              />
          <% end %>
        </div>
      </div>
      <DawarichWeb.ImportsExtractionDialog.dialog
        :if={not @no_waypoints}
        id={@id}
        locale={@locale}
        csrf={@csrf}
      />
    </turbo-frame>
    """
  end

  attr :id, :integer, required: true
  attr :class, :string, required: true
  attr :label, :string, required: true

  defp open_button(assigns) do
    ~H"""
    <button
      class={@class}
      data-action="click->import-extraction#open"
      data-import-extraction-dialog-id-param={"extraction-dialog-#{@id}"}
    >
      {@label}
    </button>
    """
  end

  attr :id, :integer, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true

  defp remove_button(assigns) do
    ~H"""
    <form
      data-turbo-confirm={
        Translate.t(
          @locale,
          "imports.extraction_remove_button.remove_the_visits_places_and_tracks_this_extraction_created_your",
          %{}
        )
      }
      class="button_to"
      method="post"
      action={"/imports/#{@id}/extraction"}
    >
      <input type="hidden" name="_method" value="delete" /><button
        class="btn btn-sm btn-ghost text-error"
        type="submit"
      >{Translate.t(@locale, "imports.extraction_remove_button.remove_extracted_data", %{})}</button><input
        type="hidden"
        name="authenticity_token"
        value={@csrf}
      />
    </form>
    """
  end

  defp text(locale, key), do: Translate.t(locale, "imports.extraction_card." <> key, %{})

  defp no_waypoints?(%{} = counts) do
    Enum.any?(@element_keys, &Map.has_key?(counts, &1)) and
      ruby_to_i(counts["waypoints_seen"]) == 0
  end

  defp no_waypoints?(_counts), do: false

  defp ruby_to_i(value) when is_integer(value), do: value
  defp ruby_to_i(value) when is_float(value), do: trunc(value)
  defp ruby_to_i(value) when is_binary(value), do: DawarichWeb.Params.ruby_to_i(value)
  defp ruby_to_i(_value), do: 0

  defp stalled?(started, now) when is_binary(started) do
    case DateTime.from_iso8601(started) do
      {:ok, at, _} -> DateTime.diff(now, at) >= @stale_after_seconds
      _ -> true
    end
  end

  defp stalled?(_started, _now), do: true
end
