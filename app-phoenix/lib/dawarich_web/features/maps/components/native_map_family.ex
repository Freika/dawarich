defmodule DawarichWeb.NativeMapFamily do
  @moduledoc false
  use DawarichWeb, :html

  attr :locale, :string, required: true
  attr :settings, :map, required: true

  def controls(assigns) do
    ~H"""
    <form id="native-map-family-layer" phx-change="settings:family_layer" hidden>
      <input type="hidden" name="enabled" value="false" />
    </form>
    <p
      id="native-family-status"
      phx-update="ignore"
      role="status"
      class="sr-only"
      data-centered={t(@locale, "javascript.messages.centered_on_family_member", %{})}
    >
    </p>
    """
  end

  attr :locale, :string, required: true
  attr :settings, :map, required: true

  def panel(assigns) do
    ~H"""
    <div id="native-map-family-panel" class="space-y-4">
      <label class="label cursor-pointer justify-start gap-3">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          form="native-map-family-layer"
          name="enabled"
          value="true"
          checked={"Family Members" in @settings.saved["enabled_map_layers"]}
        />
        <span class="label-text font-medium">{p(@locale, "show_family_member_locations")}</span>
      </label>
      <div id="native-family-list" phx-update="ignore" class="space-y-2" style="display: none;">
        <span class="layer-options__label">{p(@locale, "family_members")}</span>
        <div class="text-xs text-base-content/60">{p(@locale, "click_to_center_on_member")}</div>
        <div id="native-family-members" class="space-y-1"></div>
      </div>
      <a href="/family" class="btn btn-ghost btn-sm justify-start gap-2">
        <DawarichWeb.Icon.icon name="users" class="w-4 h-4" />
        {p(@locale, "manage_family")}
      </a>
    </div>
    """
  end

  defp p(locale, key), do: t(locale, "map.maplibre.settings_panel." <> key, %{})
end
