defmodule DawarichWeb.AdminJobHealth do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  attr :locale, :string, required: true
  attr :health, :map, required: true

  def card(assigns) do
    assigns = assign(assigns, :pretty, Dawarich.Admin.JobHealth.pretty(assigns.health.gauges))

    ~H"""
    <section id="phoenix-jobs" aria-labelledby="instance-settings-phoenix-jobs" class="mb-8">
      <h2 id="instance-settings-phoenix-jobs" class="min-w-0 text-xl font-semibold">
        {t(@locale, "admin.settings.phoenix_jobs.title", %{})}
      </h2>
      <div
        class="mt-4 min-w-0 rounded-box border border-base-content/10 bg-base-200 p-5"
        data-testid="instance-settings-phoenix-jobs"
      >
        <%= cond do %>
          <% @health.gauges["tables"] == "unknown" or @health.summary["status"] == "unknown" -> %>
            <p class="max-w-3xl [text-wrap:pretty]">
              {t(@locale, "admin.settings.phoenix_jobs.unknown", %{})}
            </p>
          <% @health.gauges["tables"] == false -> %>
            <p class="max-w-3xl [text-wrap:pretty]">
              {t(@locale, "admin.settings.phoenix_jobs.not_installed", %{})}
            </p>
          <% @health.summary["alarm"] -> %>
            <div role="alert" class="flex items-start gap-2 text-error">
              <.icon name="triangle-alert" class="size-4 shrink-0 mt-0.5" />
              <p class="min-w-0 max-w-3xl [text-wrap:pretty]">
                {t(@locale, "admin.settings.phoenix_jobs.alarm", %{})}
              </p>
            </div>
          <% true -> %>
            <p class="max-w-3xl [text-wrap:pretty]">
              {t(@locale, "admin.settings.phoenix_jobs.ok", %{})}
            </p>
        <% end %>
        <pre
          :if={@health.gauges["tables"] == true}
          class="mt-4 text-xs whitespace-pre-wrap [overflow-wrap:anywhere]"
        >{@pretty}</pre>
      </div>
    </section>
    """
  end
end
