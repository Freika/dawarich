defmodule DawarichWeb.NativePlaceFilters do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  attr :tags, :list, required: true
  attr :filters, :any, default: nil
  attr :locale, :string, required: true

  def filters(assigns) do
    selected = assigns.filters

    all =
      is_nil(selected) or
        Enum.sort(selected) == Enum.sort(["untagged" | Enum.map(assigns.tags, & &1.id)])

    assigns = assign(assigns, :all, all)

    ~H"""
    <section class="min-w-0 space-y-2">
      <button
        id="native-place-tags-all"
        type="button"
        class="btn btn-sm h-auto whitespace-normal"
        phx-click="settings:place_tags_all"
        phx-value-enabled={to_string(!@all)}
        aria-pressed={to_string(@all)}
      >{s(@locale, "enable_all_tags")}</button>
      <form id="native-place-filter" phx-change="settings:place_tags" class="space-y-2 min-w-0">
        <fieldset class="flex min-w-0 flex-wrap gap-2">
          <legend class="text-sm">{s(@locale, "click_tags_to_filter_places")}</legend>
          <input type="hidden" name="place_tag_ids[]" value="" />
          <label class="flex min-w-0 items-center gap-1">
            <input
              type="checkbox"
              name="place_tag_ids[]"
              value="untagged"
              checked={is_nil(@filters) or "untagged" in @filters}
              class="checkbox checkbox-xs"
            />
            <span class={"badge #{if !is_nil(@filters) && "untagged" not in @filters, do: "badge-outline"}"}>{s(
              @locale,
              "untagged"
            )}</span>
          </label>
          <label :for={tag <- @tags} class="flex min-w-0 flex-wrap items-center gap-1">
            <input
              type="checkbox"
              name="place_tag_ids[]"
              value={to_string(tag.id)}
              checked={is_nil(@filters) or tag.id in @filters}
              class="checkbox checkbox-xs"
            />
            <span
              data-place-tag-name={tag.name}
              style={"border-color: #{tag.color}; color: #{tag.color};"}
              class={"badge min-w-0 border rounded px-1 [overflow-wrap:anywhere] #{if !is_nil(@filters) && tag.id not in @filters, do: "badge-outline"}"}
            >{tag.icon} {tag.name}</span>
          </label>
        </fieldset>
      </form>
    </section>
    """
  end

  defp s(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
