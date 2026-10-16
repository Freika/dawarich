defmodule DawarichWeb.NativeMapFamily do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]

  attr :locale, :string, required: true
  attr :settings, :map, required: true

  def panel(assigns) do
    ~H"""
    <section id="native-map-family-panel" class="min-w-0 w-full max-w-96 bg-base-100 p-3">
      <h2>{t(@locale, "map.maplibre.button_cluster.family", %{})}</h2>
      <form id="native-map-family-layer" phx-change="settings:family_layer">
        <input type="hidden" name="enabled" value="false" />
        <label class="flex flex-wrap items-center gap-2">
          <input
            type="checkbox"
            name="enabled"
            value="true"
            class="toggle toggle-primary"
            checked={"Family Members" in @settings.saved["enabled_map_layers"]}
          />
          {t(@locale, "map.maplibre.settings_panel.family_members", %{})}
        </label>
      </form>
      <div id="native-family-members" phx-update="ignore" class="min-w-0" hidden></div>
      <p id="native-map-family-empty" phx-update="ignore" data-map-family-empty hidden>
        {t(@locale, "javascript.family.none_sharing", %{})}
      </p>
      <p
        id="native-family-status"
        phx-update="ignore"
        role="status"
        data-centered={t(@locale, "javascript.messages.centered_on_family_member", %{})}
      >
      </p>
      <a href="/family" class="btn btn-sm h-auto whitespace-normal">{t(
        @locale,
        "map.maplibre.settings_panel.manage_family",
        %{}
      )}</a>
    </section>
    """
  end
end
