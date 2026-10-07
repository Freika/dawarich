defmodule DawarichWeb.AdminExperimental do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Experimental
  alias DawarichWeb.AdminSettingField
  import DawarichWeb.Icon, only: [icon: 1]

  embed_templates "admin_experimental/*"

  attr :locale, :string, required: true
  attr :data, :map, required: true
  attr :rails_csrf_token, :string, required: true

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
            id={"phx-experimental-" <> to_string(entry.key)}
            phx-update="ignore"
            action="/admin/settings"
            method="post"
            data-turbo="false"
          >
            <input type="hidden" name="_method" value="patch" />
            <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
            <input type="hidden" name="section" value="experimental" />
            <div class="divide-y divide-base-content/10">
              <AdminSettingField.field
                :for={key <- entry.config ++ entry.toggles}
                locale={@locale}
                field={@data.fields[to_string(key)]}
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
            >
              {t(@locale, "admin.settings.show.save", %{})}
            </button>
          </form>
          <form
            :if={entry.key == :map_matching}
            action="/admin/settings/test_map_matching"
            method="post"
            data-turbo="false"
            class="self-start"
          >
            <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
            <button type="submit" class="btn btn-sm btn-outline">{t(
              @locale,
              "admin.settings.show.map_matching.test",
              %{}
            )}</button>
          </form>
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
