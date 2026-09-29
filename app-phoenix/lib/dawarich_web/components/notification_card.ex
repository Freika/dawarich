defmodule DawarichWeb.NotificationCard do
  @moduledoc false
  use DawarichWeb, :html

  attr :notification, :map, required: true
  attr :locale, :string, required: true
  attr :now, :any, required: true
  attr :show_content, :boolean, default: false

  def card(assigns) do
    ~H"""
    <div
      role={@notification.kind}
      class={"#{@notification.kind} shadow-lg p-5 flex justify-between items-center mb-4 rounded-lg bg-base-200"}
      id={
        if @show_content,
          do: "detail_notification_#{@notification.id}",
          else: "notification_#{@notification.id}"
      }
    >
      <div class="flex-1 min-w-0 [overflow-wrap:anywhere]">
        <h3 class="font-bold text-xl">
          <a
            class={"link hover:no-underline #{if @notification.read_at, do: "text-gray-600", else: "text-blue-600"}"}
            href={"/notifications/#{@notification.id}"}
          >{@notification.title}</a>
        </h3>
        <div class="text-sm text-gray-500">
          {t(@locale, "common.time_ago", %{
            time: DawarichWeb.TimeAgo.words(@locale, @notification.created_at, @now)
          })}
        </div>
        <div :if={@show_content} class="mt-2">
          {Phoenix.HTML.raw(Dawarich.HtmlSanitizer.sanitize(@notification.content))}
          <div :if={@notification.kind == "error"} class="mt-2">
            {t(@locale, "notifications.notification.please_when_reporting_a_bug_to", %{})} <a
              href="https://github.com/Freika/dawarich/issues"
              class="link hover:no-underline text-blue-600"
            >{t(@locale, "notifications.notification.github_issues", %{})}</a>{t(
              @locale,
              "notifications.notification.don_t_forget_to_include_logs_from",
              %{}
            )}
            <code>{t(@locale, "notifications.notification.dawarich_app", %{})}</code> {t(
              @locale,
              "notifications.notification.and",
              %{}
            )}
            <code>{t(@locale, "notifications.notification.dawarich_sidekiq", %{})}</code> {t(
              @locale,
              "notifications.notification.docker_containers_thank_you",
              %{}
            )}
          </div>
        </div>
      </div>
      <div class={"badge badge-#{@notification.kind} gap-2"}></div>
    </div>
    """
  end
end
