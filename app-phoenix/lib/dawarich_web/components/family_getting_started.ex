defmodule DawarichWeb.FamilyGettingStarted do
  @moduledoc false
  use DawarichWeb, :html

  def getting_started(assigns) do
    assigns =
      assign(assigns,
        invite?:
          assigns.page.owner? and assigns.page.member_count == 1 and
            assigns.page.invitations == []
      )

    ~H"""
    <div id="family-getting-started-slot">
      <div
        :if={@invite? or !@page.me.sharing.enabled?}
        id="family-getting-started"
        class="border border-primary/30 bg-primary/5 rounded-xl p-5 mb-4"
      >
        <div class="flex flex-col lg:flex-row lg:items-start gap-5">
          <div class="flex-1 min-w-0">
            <%= if @invite? do %>
              <h2 class="text-lg font-semibold mb-1">{g(@locale, "invite_title")}</h2>
              <p class="text-sm text-base-content/70 mb-3">{g(@locale, "invite_body")}</p>
              <DawarichWeb.FamilyMembers.invite_form
                page={@page}
                locale={@locale}
                rails_csrf_token={@rails_csrf_token}
                getting_started={true}
              />
              <p :if={!@self_hosted} class="text-xs text-base-content/50 mt-2">
                {g(@locale, "seats", %{used: @page.member_count, total: 5})}
              </p>
              <p :if={!@self_hosted} class="text-xs text-base-content/50 mt-1">
                {g(@locale, "members_lose_access_when_your_plan_ends")}
              </p>
            <% else %>
              <h2 class="text-lg font-semibold mb-1">{g(@locale, "sharing_title")}</h2>
              <p class="text-sm text-base-content/70">{g(@locale, "sharing_body")}</p>
            <% end %>
            <p :if={@page.owner? and @page.trial_ends} class="text-xs text-base-content/60 mt-3">
              <DawarichWeb.Icon.icon name="clock" class="w-3.5 h-3.5 inline" />
              {g(@locale, "trial_ends_on", %{
                date: DawarichWeb.LocalizedDate.l(@locale, @page.trial_ends, "long")
              })}
            </p>
          </div>
          <div class="lg:w-64 lg:border-l lg:border-primary/20 lg:pl-5">
            <h3 class="text-sm font-medium mb-1">{g(@locale, "app_title")}</h3>
            <p class="text-xs text-base-content/60 mb-3">{g(@locale, "app_body")}</p>
            <div class="flex flex-wrap items-center gap-2">
              <a
                href="https://apps.apple.com/de/app/dawarich/id6739544999"
                class="inline-block"
                target="_blank"
                rel="noopener"
              ><img
                src="/assets/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg"
                class="h-[34px]"
              /></a>
              <a
                href="https://play.google.com/store/apps/details?id=app.dawarich.Dawarich"
                class="inline-block"
                target="_blank"
                rel="noopener"
              ><img src="/assets/GetItOnGooglePlay_Badge_Web_color_English.svg" class="h-[34px]" /></a>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp g(locale, key, bindings \\ %{}),
    do: t(locale, "families.getting_started." <> key, bindings)
end
