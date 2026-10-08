defmodule DawarichWeb.Chrome do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]
  alias DawarichWeb.Icon
  alias Phoenix.LiveView.JS

  attr :locale, :string, required: true
  attr :flash_messages, :list, default: []
  attr :flash, :map, default: %{}
  attr :native, :boolean, default: false

  def flash(assigns) do
    messages = Map.to_list(assigns.flash) ++ assigns.flash_messages
    assigns = assign(assigns, :messages, messages)

    ~H"""
    <div class="fixed top-5 right-5 flex flex-col gap-2 z-50" id="flash-messages">
      <%= for {type, message} <- @messages do %>
        <.flash_message type={type} message={message} locale={@locale} native={@native} />
      <% end %>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :message, :any, required: true
  attr :locale, :string, required: true
  attr :native, :boolean, default: false

  def flash_message(assigns) do
    assigns =
      assign(assigns,
        class: flash_class(assigns.type),
        icon: flash_icon(assigns.type),
        timeout: if(to_string(assigns.type) in ["notice", "success"], do: 5000, else: 0)
      )

    ~H"""
    <div
      data-controller={!@native && "removals"}
      data-removals-timeout-value={!@native && @timeout}
      phx-mounted={@timeout == 5000 && JS.dispatch("dawarich:flash-timeout")}
      role="alert"
      class={"alert #{@class} shadow-lg z-[6000]"}
    >
      <div class="flex items-center gap-2">
        <Icon.icon name={@icon} class="size-6" /><span>{@message}</span>
      </div>
      <button
        type="button"
        data-action={!@native && "click->removals#remove"}
        phx-click={dismiss(@type)}
        class="btn btn-sm btn-circle btn-ghost"
        aria-label={t(@locale, "shared.flash_message.close", %{})}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        ><path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M6 18L18 6M6 6l12 12"
        /></svg>
      </button>
    </div>
    """
  end

  attr :user_id, :integer, required: true

  def achievement_host(assigns) do
    ~H"""
    <div
      id="achievement-unlocks"
      class="ach-unlock-host"
      aria-live="polite"
      phx-hook="RailsStimulus"
      phx-update="ignore"
      data-controller="achievement-unlocks"
      data-achievement-unlocks-user-id-value={@user_id}
      data-achievement-unlocks-next-url-value="/achievements/unlocks/next"
      data-achievement-unlocks-seen-url-value="/achievements/unlocks/__ID__/seen"
      data-achievement-unlocks-dismiss-url-value="/achievements/unlocks/dismiss"
      data-action="turbo:before-cache@document->achievement-unlocks#beforeCache keydown@window->achievement-unlocks#keyDown visibilitychange@document->achievement-unlocks#resumeVisit pageshow@window->achievement-unlocks#resumeVisit"
    >
    </div>
    """
  end

  def footer(assigns),
    do: ~H"""
    <footer class="footer bg-base-200 text-content-neutral p-4">
      <aside>
        <p>
          <a href="https://dawarich.app/" class="link hover:no-underline" target="_blank">{t(
            @locale,
            "shared.footer.dawarich",
            %{}
          )}</a>
          2023-{@now.year}
        </p>
      </aside>
    </footer>
    """

  def legal_footer(assigns),
    do: ~H"""
    <footer class="footer bg-base-200 text-content-neutral p-4">
      <nav>
        <h6 class="footer-title">
          <strong>{t(@locale, "shared.legal_footer.dawarich", %{})}</strong>
        </h6><p>{t(@locale, "shared.legal_footer.made_and_hosted_in_europe", %{})}</p><p>
          {t(@locale, "shared.legal_footer.copyright", %{})} {@now.year} {t(
            @locale,
            "shared.legal_footer.zeitflow_ug",
            %{}
          )}
        </p>
      </nav>
      <nav>
        <h6 class="footer-title">
          <strong>{t(@locale, "shared.legal_footer.community", %{})}</strong>
        </h6>
        <a class="hover:underline" href="https://discord.gg/pHsBjpt5J8" target="_blank">{t(
          @locale,
          "shared.legal_footer.discord",
          %{}
        )}</a>
        <a class="hover:underline" href="https://x.com/freymakesstuff" target="_blank">X</a>
        <a class="hover:underline" href="https://github.com/Freika/dawarich" target="_blank">{t(
          @locale,
          "shared.legal_footer.github",
          %{}
        )}</a>
        <a class="hover:underline" href="https://mastodon.social/@dawarich" target="_blank">{t(
          @locale,
          "shared.legal_footer.mastodon",
          %{}
        )}</a>
      </nav>
      <nav>
        <h6 class="footer-title"><strong>{t(@locale, "shared.legal_footer.docs", %{})}</strong></h6>
        <a class="hover:underline" href="https://dawarich.app/docs/intro" target="_blank">{t(
          @locale,
          "shared.legal_footer.tutorial",
          %{}
        )}</a>
        <a
          class="hover:underline"
          href="https://dawarich.app/docs/tutorials/import-existing-data"
          target="_blank"
        >{t(@locale, "shared.legal_footer.import_existing_data", %{})}</a>
        <a
          class="hover:underline"
          href="https://dawarich.app/docs/tutorials/export-your-data"
          target="_blank"
        >{t(@locale, "shared.legal_footer.exporting_data", %{})}</a>
        <a class="hover:underline" href="https://dawarich.app/docs/FAQ" target="_blank">{t(
          @locale,
          "shared.legal_footer.faq",
          %{}
        )}</a>
        <a class="hover:underline" href="https://dawarich.app/contact" target="_blank">{t(
          @locale,
          "shared.legal_footer.contact",
          %{}
        )}</a>
      </nav>
      <nav>
        <h6 class="footer-title"><strong>{t(@locale, "shared.legal_footer.more", %{})}</strong></h6>
        <a class="hover:underline" href="https://dawarich.app/privacy-policy" target="_blank">{t(
          @locale,
          "shared.legal_footer.privacy_policy",
          %{}
        )}</a>
        <a class="hover:underline" href="https://dawarich.app/terms-and-conditions" target="_blank">{t(
          @locale,
          "shared.legal_footer.terms_and_conditions",
          %{}
        )}</a>
        <a class="hover:underline" href="https://dawarich.app/refund-policy" target="_blank">{t(
          @locale,
          "shared.legal_footer.refund_policy",
          %{}
        )}</a>
        <a class="hover:underline" href="https://dawarich.app/impressum" target="_blank">{t(
          @locale,
          "shared.legal_footer.impressum",
          %{}
        )}</a>
        <a class="hover:underline" href="https://dawarich.app/blog" target="_blank">{t(
          @locale,
          "shared.legal_footer.blog",
          %{}
        )}</a>
      </nav>
    </footer>
    """

  defp dismiss(type) do
    JS.hide(to: {:closest, "[role='alert']"}, transition: "fade-out", time: 150)
    |> JS.push("lv:clear-flash", value: %{key: to_string(type)})
  end

  defp flash_class(type) when type in [:notice, :success, "notice", "success"],
    do: "alert-success"

  defp flash_class(type) when type in [:alert, :error, "alert", "error"], do: "alert-error"
  defp flash_class(type) when type in [:warning, "warning"], do: "alert-warning"
  defp flash_class(_), do: "alert-info"
  defp flash_icon(type) when type in [:notice, :success, "notice", "success"], do: "circle-check"
  defp flash_icon(type) when type in [:alert, :error, "alert", "error"], do: "circle-x"
  defp flash_icon(type) when type in [:warning, "warning"], do: "circle-alert"
  defp flash_icon(_), do: "info"
end
