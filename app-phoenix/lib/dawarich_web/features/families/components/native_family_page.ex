defmodule DawarichWeb.NativeFamilyPage do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  def page(assigns) do
    ~H"""
    <DawarichWeb.NativeMapChrome.header {assigns} />
    <DawarichWeb.Chrome.flash locale={@locale} flash={@flash} native />
    <div :if={@page} id="family-shell" data-native-map-root>
      <div id="native-family-page" class="w-full my-5">
        <DawarichWeb.FamilyNativeControls.errors errors={@errors} />
        <DawarichWeb.ListParts.page_header title={@page.presentation.family.name}>
          <div class="flex items-center gap-2">
            <a :if={@page.presentation.owner?} href="/family/edit" class="btn btn-outline btn-sm"><.icon
              name="square-pen"
              class="w-4 h-4"
            /> {s(@locale, "edit")}</a>
            <button
              :if={@page.presentation.owner? && @page.presentation.can_invite?}
              class="btn btn-primary btn-sm"
              id="native-family-invite-scroll"
              phx-hook="FamilyInviteScroll"
            ><.icon name="circle-plus" class="w-4 h-4" /> {s(@locale, "invite")}</button>
          </div>
        </DawarichWeb.ListParts.page_header>
        <div class="text-sm text-base-content/50 -mt-4 mb-6">
          {s(@locale, "members_created", %{
            count: @page.presentation.member_count,
            date:
              DawarichWeb.LocalizedDate.l(
                @locale,
                @page.presentation.family.created_date,
                "month_year"
              )
          })}
        </div>
        <DawarichWeb.NativeFamilyGettingStarted.getting_started
          page={@page.presentation}
          locale={@locale}
          self_hosted={@self_hosted != false}
        />
        <div class="flex flex-col lg:flex-row gap-4" style="min-height: 500px;">
          <div class="w-full lg:w-3/5 min-h-full">
            <DawarichWeb.FamilyMap.family_map config={@page.config} locale={@locale} />
          </div>
          <div class="w-full lg:w-2/5 flex flex-col gap-4">
            <DawarichWeb.NativeFamilySharing.sharing
              member={@page.presentation.me}
              locale={@locale}
              now={@now}
            />
            <DawarichWeb.NativeFamilyPageMembers.members
              page={@page.presentation}
              locale={@locale}
              now={@now}
              self_hosted={@self_hosted}
            />
            <DawarichWeb.NativeFamilyInvitations.invitations
              self_hosted={@self_hosted != false}
              page={@page.presentation}
              locale={@locale}
              now={@now}
              base_url={@base_url || ""}
            />
            <DawarichWeb.FamilyNativeControls.danger page={@page.presentation} locale={@locale} />
          </div>
        </div>
      </div>
      <DawarichWeb.FamilyNativeControls.confirmation
        confirmation={@confirmation}
        page={@page.presentation}
        locale={@locale}
      />
    </div>
    <p :if={@map_error} role="alert">{to_string(@map_error)}</p>
    """
  end

  defp s(locale, key, bindings \\ %{}), do: t(locale, "families.show." <> key, bindings)
end
