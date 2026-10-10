defmodule DawarichWeb.NativeFamilyGettingStarted do
  @moduledoc false
  use DawarichWeb, :html
  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :self_hosted, :boolean, required: true

  def getting_started(assigns) do
    assigns =
      assign(
        assigns,
        :invite?,
        assigns.page.owner? && assigns.page.member_count == 1 && assigns.page.invitations == []
      )

    ~H"""
    <section
      :if={@invite? || !@page.me.sharing.enabled?}
      id="family-getting-started"
      class="min-w-0 border border-primary/30 bg-primary/5 rounded-xl p-5 my-4 [overflow-wrap:anywhere]"
    >
      <div class="flex flex-col lg:flex-row min-w-0 gap-5">
        <div class="flex-1 min-w-0">
          <h2 class="text-lg font-semibold">
            {g(@locale, if(@invite?, do: "invite_title", else: "sharing_title"))}
          </h2>
          <p class="text-sm my-3">
            {g(@locale, if(@invite?, do: "invite_body", else: "sharing_body"))}
          </p>
          <a
            :if={@invite?}
            href="#native-family-invite"
            class="btn btn-primary btn-sm h-auto whitespace-normal"
          >{t(@locale, "families.show.invite", %{})}</a>
          <p :if={!@self_hosted} class="text-xs">
            {g(@locale, "seats", %{used: @page.member_count, total: 5})}
          </p>
          <p :if={!@self_hosted} class="text-xs">
            {g(@locale, "members_lose_access_when_your_plan_ends")}
          </p>
          <p :if={@page.owner? && @page.trial_ends} class="text-xs">
            {g(@locale, "trial_ends_on", %{
              date: DawarichWeb.LocalizedDate.l(@locale, @page.trial_ends, "long")
            })}
          </p>
        </div>
        <div class="min-w-0 lg:w-64">
          <h3 class="text-sm font-medium">{g(@locale, "app_title")}</h3>
          <p class="text-xs mb-3">{g(@locale, "app_body")}</p>
          <div class="flex flex-wrap min-w-0 gap-2">
            <a
              href="https://apps.apple.com/de/app/dawarich/id6739544999"
              target="_blank"
              rel="noopener"
            ><img
              src="/assets/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg"
              alt="App Store"
              class="h-[34px] max-w-full"
            /></a>
            <a
              href="https://play.google.com/store/apps/details?id=app.dawarich.Dawarich"
              target="_blank"
              rel="noopener"
            ><img
              src="/assets/GetItOnGooglePlay_Badge_Web_color_English.svg"
              alt="Google Play"
              class="h-[34px] max-w-full"
            /></a>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp g(locale, key, bindings \\ %{}),
    do: t(locale, "families.getting_started." <> key, bindings)
end
