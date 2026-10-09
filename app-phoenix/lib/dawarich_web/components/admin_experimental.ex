defmodule DawarichWeb.AdminExperimental do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Experimental
  alias DawarichWeb.AdminSettingField
  import DawarichWeb.Icon, only: [icon: 1]

  embed_templates "admin_experimental/*"

  attr :locale, :string, required: true
  attr :data, :map, required: true
  attr :testing, :any, required: true
  attr :saves, :integer, required: true

  def section(assigns) do
    assigns = assign(assigns, :entries, Experimental.entries())

    ~H"""
    <section
      class="space-y-6 max-w-3xl"
      data-testid="instance-settings-pane-experimental"
      aria-labelledby="experimental-title"
    >
      <h2 id="experimental-title" class="text-xl font-semibold">
        {t(@locale, "admin.settings.show.experimental.title", %{})}
      </h2>
      <article
        :for={entry <- @entries}
        class="rounded-box border border-base-content/10 bg-base-200"
        data-testid={"experimental-" <> to_string(entry.key)}
      >
        <div class="card-body min-w-0">
          <div class="flex flex-wrap items-center gap-3">
            <h3 class="text-lg font-semibold">{t(@locale, entry.label, %{})}</h3>
            <span class="badge badge-warning badge-outline">{t(
              @locale,
              "admin.settings.show.experimental.badge",
              %{}
            )}</span>
          </div>
          <p class="text-sm text-base-content/70 [text-wrap:pretty]">
            {t(@locale, entry.description, %{})}
          </p>
          <%= if entry.key == :map_matching do %>
            <.demo locale={@locale} />
            <div role="note" class="flex items-start gap-2 text-sm">
              <.icon name="shield" class="size-4 shrink-0 mt-0.5" />
              <p class="min-w-0 [text-wrap:pretty]">
                {t(@locale, "admin.settings.show.map_matching.privacy", %{})}
              </p>
            </div>
          <% end %>
          <form
            id={"experimental-" <> to_string(entry.key) <> "-#{@saves}"}
            data-testid="instance-settings-form-experimental"
            phx-submit="save"
          >
            <input type="hidden" name="section" value="experimental" />
            <div class="divide-y divide-base-content/10">
              <AdminSettingField.field
                :for={key <- Enum.map(entry.config ++ entry.toggles, &to_string/1)}
                locale={@locale}
                field={@data.fields[key]}
              />
            </div>
            <p
              :if={missing_prerequisite?(entry, @data)}
              role="note"
              class="text-sm text-warning mb-4"
              data-testid="experimental-prerequisite"
            >
              {t(@locale, "admin.settings.update.atlas_url_required", %{})}
            </p>
            <button
              :if={
                Enum.any?(entry.config ++ entry.toggles, &(not @data.fields[to_string(&1)].pinned))
              }
              type="submit"
              class="btn btn-primary"
              phx-disable-with={t(@locale, "admin.settings.show.saving", %{})}
            >
              {t(@locale, "admin.settings.show.save", %{})}
            </button>
          </form>
          <button
            :if={entry.key == :map_matching}
            id="test-map-matching"
            type="button"
            class="btn btn-sm btn-outline self-start"
            phx-click="test_map_matching"
            disabled={MapSet.member?(@testing, :map_matching)}
          >{t(@locale, "admin.settings.show.map_matching.test", %{})}</button>
        </div>
      </article>
    </section>
    """
  end

  defp missing_prerequisite?(entry, data) do
    Enum.any?(entry.prerequisites, fn {_toggle, prerequisites} ->
      Enum.any?(prerequisites, &(not data.fields[to_string(&1)].present))
    end)
  end
end
