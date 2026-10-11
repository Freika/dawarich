defmodule DawarichWeb.NativeMapEnrichment do
  @moduledoc false
  use Phoenix.Component

  import DawarichWeb.Translate, only: [t: 3]

  attr :enrichment, :map, default: nil
  attr :start_date, :string, required: true
  attr :end_date, :string, required: true
  attr :locale, :string, required: true

  def tool(assigns) do
    ~H"""
    <section id="native-map-enrichment" class="space-y-2 min-w-0">
      <h3 class="font-semibold text-sm">{p(@locale, "enrich_photos")}</h3>
      <p class="text-xs text-base-content/70">
        {p(@locale, "match_immich_photos_without_gps_to_your_location_history")}
      </p>
      <form
        id="native-enrichment-scan"
        phx-submit="enrichment:scan"
        class="flex flex-wrap items-end gap-2"
      >
        <label class="form-control min-w-0">
          <span class="label-text text-xs">{p(@locale, "from")}</span>
          <input
            type="date"
            name="start_date"
            value={@start_date}
            class="input input-xs input-bordered"
          />
        </label>
        <label class="form-control min-w-0">
          <span class="label-text text-xs">{p(@locale, "to")}</span>
          <input type="date" name="end_date" value={@end_date} class="input input-xs input-bordered" />
        </label>
        <label class="form-control min-w-0">
          <span class="label-text text-xs">{p(@locale, "tolerance_minutes")}</span>
          <select name="tolerance" class="select select-xs select-bordered">
            <option
              :for={minutes <- [5, 15, 30, 60, 120]}
              value={minutes * 60}
              selected={minutes == 30}
            >
              {minutes}
            </option>
          </select>
        </label>
        <button type="submit" class="btn btn-xs btn-primary" disabled={scanning?(@enrichment)}>
          {if scanning?(@enrichment),
            do: p(@locale, "scanning_immich_photos"),
            else: p(@locale, "scan_for_matches")}
        </button>
      </form>
      <div
        id="native-enrichment-results"
        phx-update="ignore"
        data-enrichment-results
        data-labels={Jason.encode!(labels(@locale))}
        class="space-y-2 min-w-0"
      >
        <label class="flex flex-wrap items-center gap-2 text-xs">
          <input type="checkbox" data-enrichment-all class="checkbox checkbox-xs" />
          {t(@locale, "points.index.select_all", %{})}
        </label>
        <div data-enrichment-list class="max-h-72 overflow-y-auto min-w-0"></div>
        <button
          type="button"
          data-enrichment-submit
          disabled
          class="btn btn-xs btn-primary h-auto whitespace-normal"
        >
          {t(@locale, "javascript.immich.enrich_photos", %{count: 0})}
        </button>
        <p data-enrichment-status role="status" class="text-xs [overflow-wrap:anywhere]"></p>
      </div>
      <p
        :if={@enrichment && @enrichment.status == :ready}
        class="text-xs"
        data-enrichment-matched={@enrichment.matched}
      >
        {if @enrichment.matched == 0,
          do: t(@locale, "javascript.immich.no_matches", %{}),
          else:
            t(@locale, "javascript.immich.matched_summary", %{
              matched: @enrichment.matched,
              total: @enrichment.total
            })}
      </p>
      <p
        :if={@enrichment && match?({:error, _}, @enrichment.status)}
        class="alert alert-error text-xs"
        role="alert"
      >
        {t(@locale, "javascript.messages.failed_to_scan_photos", %{})}
      </p>
    </section>
    """
  end

  defp labels(locale) do
    keys =
      ~w(enrich_photos confirm_enrich enriching pending_enrichment partially_enriched enriched)

    labels =
      Map.new(keys, fn key ->
        path = "javascript.immich." <> key

        value =
          case Dawarich.I18n.template(locale, path) do
            {:ok, text} ->
              String.replace(text, "%{", "{")

            _ ->
              Map.new(~w(one other), fn form ->
                {:ok, text} = Dawarich.I18n.template(locale, path <> "." <> form)
                {form, String.replace(text, "%{", "{")}
              end)
          end

        {key, value}
      end)

    Map.put(labels, "failed", t(locale, "javascript.messages.failed_to_enrich_photos", %{}))
  end

  defp scanning?(enrichment), do: match?(%{status: :scanning}, enrichment)
  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
