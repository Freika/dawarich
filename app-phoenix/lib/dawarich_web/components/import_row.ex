defmodule DawarichWeb.ImportRow do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]
  import DawarichWeb.Icon, only: [brand: 1, icon: 1]
  import DawarichWeb.ListParts, only: [status_badge: 1]

  alias DawarichWeb.{HumanSize, NumberFormat}

  @google {"bg-error/10 text-error", :google}
  @styles %{
    "google_semantic_history" => @google,
    "google_phone_takeout" => @google,
    "google_records" => @google,
    "google_photos" => @google,
    "gpx" => {"bg-success/10 text-success", "route"},
    "owntracks" => {"bg-primary/10 text-primary", "map-pin"},
    "geojson" => {"bg-warning/10 text-warning", "earth"},
    "immich_api" => {"bg-info/10 text-info", "camera"},
    "photoprism_api" => {"bg-info/10 text-info", "camera"},
    "kml" => {"bg-warning/10 text-warning", "earth"},
    "user_data_archive" => {"bg-base-200 text-base-content/50", "file-up"}
  }
  @fallback {"bg-base-200 text-base-content/50", "file-up"}
  @extraction %{
    "pending" => "badge-info",
    "running" => "badge-info gap-1",
    "completed" => "badge-success",
    "failed" => "badge-error"
  }

  attr :import, :map, required: true
  attr :locale, :string, required: true
  attr :now, :any, required: true
  attr :rails_csrf_token, :string, default: nil

  def row(assigns) do
    {css, source_icon} = Map.get(@styles, assigns.import.source, @fallback)

    assigns =
      assign(assigns,
        css: css,
        source_icon: source_icon,
        extraction: Map.get(@extraction, assigns.import.extraction),
        state: state(assigns.import, assigns.now)
      )

    ~H"""
    <tr
      data-import-id={@import.id}
      id={"import_#{@import.id}"}
      data-points-total={to_string(@import.processed)}
      class="hover:bg-base-200/50 transition-colors"
    >
      <td class="px-4 py-3">
        <div class="flex items-center gap-3">
          <div class={"w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 " <> @css}>
            <.brand :if={@source_icon == :google} name="google" class="w-4 h-4" />
            <.icon :if={@source_icon != :google} name={@source_icon} class="w-4 h-4" />
          </div>
          <div>
            <div class="font-medium">
              <a href={"/imports/#{@import.id}"} class="link link-hover">{@import.name}</a>
              <span :if={@import.demo} class="badge badge-accent badge-sm ml-1">{t(
                @locale,
                "imports.table_row.demo",
                %{}
              )}</span>
            </div>
            <div class="text-xs text-base-content/50">
              {@import.source && t(@locale, "enums.import.source." <> @import.source, %{})}
            </div>
          </div>
        </div>
      </td>
      <td class="px-4 py-3 text-sm">
        {HumanSize.format(@locale, @import.byte_size) || t(@locale, "common.not_available", %{})}
      </td>
      <td class="px-4 py-3 text-right tabular-nums font-medium" data-points-count>
        {@import.processed && NumberFormat.delimited(@locale, @import.processed)}
        <div
          :if={(@import.doubles || 0) > 0}
          class="text-xs font-normal text-base-content/60 mt-0.5"
          title={
            t(
              @locale,
              "imports.table_row.points_at_coordinates_and_timestamps_that_already_exist_in_your",
              %{}
            )
          }
        >
          {NumberFormat.delimited(@locale, @import.doubles)} {t(
            @locale,
            "imports.table_row.already_imported",
            %{}
          )}
        </div>
      </td>
      <td class="px-4 py-3" data-status-display>
        <div class="flex flex-col gap-1 items-start">
          <.status_badge record={@import} locale={@locale} />
          <span :if={@extraction} class={"badge badge-sm " <> @extraction}><span
            :if={@import.extraction == "running"}
            class="loading loading-dots loading-xs shrink-0"
          ></span>{t(@locale, "helpers.imports.extraction_status." <> @import.extraction, %{})}</span>
        </div>
      </td>
      <td class="px-4 py-3 text-sm text-base-content/50">
        <.human_datetime locale={@locale} at={@import.created} />
      </td>
      <td class="px-4 py-3 text-right">
        <div class="flex items-center gap-1 justify-end">
          <%= case @state do %>
            <% :deleting -> %>
              <span class="loading loading-spinner loading-sm"></span>
              <span class="text-xs text-base-content/50">{t(
                @locale,
                "imports.table_row.deleting",
                %{}
              )}</span>
            <% :stalled -> %>
              <span class="text-xs text-base-content/50">{t(
                @locale,
                "imports.table_row.deletion_stalled",
                %{}
              )}</span>
              <div
                class="tooltip tooltip-left"
                data-tip={t(@locale, "imports.table_row.retry_deletion", %{})}
              >
                <.delete_link
                  id={@import.id}
                  locale={@locale}
                  native={@import.source == "gpx"}
                  rails_csrf_token={@rails_csrf_token}
                />
              </div>
            <% :listed -> %>
              <div class="tooltip" data-tip={t(@locale, "imports.table_row.view_on_map", %{})}>
                <a href={"/map/v2?import_id=#{@import.id}"} class="btn btn-ghost btn-xs"><.icon
                  name="map"
                  class="w-4 h-4"
                /></a>
              </div>
              <div class="tooltip" data-tip={t(@locale, "imports.table_row.view_points", %{})}>
                <a href={"/points?import_id=#{@import.id}"} class="btn btn-ghost btn-xs"><.icon
                  name="grid-3x3"
                  class="w-4 h-4"
                /></a>
              </div>
              <div
                :if={@import.byte_size}
                class="tooltip"
                data-tip={t(@locale, "imports.table_row.download_file", %{})}
              >
                <a
                  href={"/imports/#{@import.id}/download"}
                  class="btn btn-ghost btn-xs"
                  data-turbo="false"
                ><.icon
                  name="arrow-big-down"
                  class="w-4 h-4"
                /></a>
              </div>
              <div
                class="tooltip tooltip-left"
                data-tip={t(@locale, "imports.table_row.delete_import", %{})}
              >
                <.delete_link
                  id={@import.id}
                  locale={@locale}
                  native={@import.source == "gpx"}
                  rails_csrf_token={@rails_csrf_token}
                />
              </div>
          <% end %>
        </div>
      </td>
    </tr>
    """
  end

  attr :id, :integer, required: true
  attr :locale, :string, required: true
  attr :native, :boolean, required: true
  attr :rails_csrf_token, :string, default: nil

  defp delete_link(%{native: false} = assigns) do
    ~H"""
    <a
      href={"/imports/#{@id}"}
      class="btn btn-ghost btn-xs text-error hover:bg-error/10"
      data-turbo-confirm={t(@locale, "imports.table_row.are_you_sure", %{})}
      data-turbo-method="delete"
    ><.icon name="trash-2" class="w-4 h-4" /></a>
    """
  end

  defp delete_link(assigns) do
    ~H"""
    <form action={"/imports/#{@id}"} method="post" data-turbo="false" phx-submit="delete_import">
      <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
      <input type="hidden" name="_method" value="delete" /><input
        type="hidden"
        name="import_id"
        value={@id}
      />
      <button
        type="submit"
        data-testid="import-delete"
        class="btn btn-ghost btn-xs text-error hover:bg-error/10"
        data-confirm={t(@locale, "imports.table_row.are_you_sure", %{})}
      ><.icon name="trash-2" class="w-4 h-4" /></button>
    </form>
    """
  end

  defp state(%{status: "deleting", updated_at: updated_at}, now) do
    cutoff = now |> DateTime.to_naive() |> NaiveDateTime.add(-3600)
    if NaiveDateTime.compare(updated_at, cutoff) == :gt, do: :deleting, else: :stalled
  end

  defp state(_import, _now), do: :listed
end
