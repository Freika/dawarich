defmodule DawarichWeb.PlanCards do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]

  alias DawarichWeb.NumberFormat

  attr :locale, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :trial, :boolean, required: true
  attr :trial_at, :map, default: nil
  attr :auto_converting, :boolean, required: true
  attr :manager, :string, default: nil
  attr :subscription, :string, default: nil
  attr :points, :integer, required: true

  def plan_cards(assigns) do
    ~H"""
    <%= if @trial or not @self_hosted do %>
      <div class="grid gap-4 lg:grid-cols-2">
        <div :if={@trial} class="card bg-base-100 shadow-xl">
          <div class="card-body p-5 sm:p-6">
            <h2 class="card-title text-xl">
              {t(@locale, "devise.registrations.edit.trial_status", %{})}
            </h2>
            <p class="text-sm text-base-content/70">
              {t(@locale, "devise.registrations.edit.your_trial_period_ends_at", %{})} <span class="font-medium text-base-content"><.human_datetime :if={@trial_at} locale={@locale} at={@trial_at} /></span>.
            </p>
            <div class="mt-2">
              <a :if={@auto_converting} class="btn btn-primary btn-sm glass" href={@manager}>{t(
                @locale,
                "devise.registrations.edit.manage_subscription",
                %{}
              )}</a>
              <a :if={!@auto_converting} class="btn btn-success btn-sm glass" href={@manager}>{t(
                @locale,
                "devise.registrations.edit.subscribe",
                %{}
              )}</a>
            </div>
          </div>
        </div>
        <div :if={!@self_hosted} class="card bg-base-100 shadow-xl">
          <div class="card-body p-5 sm:p-6">
            <h2 class="card-title text-xl">
              {t(@locale, "devise.registrations.edit.plan_usage", %{})}
            </h2>
            <div class="space-y-3">
              <p class="text-sm text-base-content/70">
                {t(@locale, "devise.registrations.points_usage.summary_html", %{
                  used: strong(@locale, @points),
                  limit: strong(@locale, 10_000_000)
                })}
              </p>
              <progress class="progress progress-primary h-5 w-full" value={@points} max="10000000"></progress>
            </div>
          </div>
        </div>
      </div>
      <div :if={!@self_hosted and !@trial} class="card bg-base-100 shadow-xl">
        <div class="card-body p-5 sm:p-6">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div>
              <h2 class="card-title text-xl">
                {t(@locale, "devise.registrations.edit.subscription", %{})}
              </h2>
              <p class="text-sm text-base-content/70">
                {t(@locale, "devise.registrations.edit." <> @subscription, %{})}
              </p>
            </div>
            <a class="btn btn-primary btn-sm whitespace-nowrap" href={@manager}>{t(
              @locale,
              "devise.registrations.edit.manage_subscription",
              %{}
            )}</a>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp strong(locale, number),
    do:
      {:safe,
       ~s(<span class="font-medium text-base-content">#{NumberFormat.delimited(locale, number)}</span>)}
end
