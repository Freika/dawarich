defmodule DawarichWeb.FamiliesLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view

  alias DawarichWeb.{
    FamilyNativeControls,
    FamilyNativeInvitations,
    FamilyNativeMembers,
    FamilyNativeLive
  }

  alias Phoenix.LiveView.JS

  @impl true
  def mount(_, _, socket), do: {:ok, FamilyNativeLive.mount(socket)}
  @impl true
  def handle_event(event, params, socket), do: FamilyNativeLive.event(event, params, socket)
  @impl true
  def handle_info(_, socket), do: {:noreply, socket}
  @impl true
  def handle_params(_, _, socket), do: {:noreply, socket}
  @impl true
  def render(assigns) do
    ~H"""
    <section id="family-shell" class="w-full my-5 min-w-0 [overflow-wrap:anywhere]">
      <FamilyNativeControls.errors errors={@errors} />
      <header class="flex flex-wrap gap-3 justify-between items-center mb-4">
        <h1 class="text-3xl font-bold min-w-0">{@page.family.name}</h1>
        <div :if={@page.owner?} class="flex flex-wrap gap-2">
          <a href="/family/edit" class="btn btn-outline btn-sm h-auto whitespace-normal">{t(
            @locale,
            "families.show.edit",
            %{}
          )}</a>
          <button
            :if={@page.can_invite?}
            type="button"
            phx-click={JS.focus(to: "#native-invite-email")}
            class="btn btn-primary btn-sm h-auto whitespace-normal"
          >{t(@locale, "families.show.invite", %{})}</button>
        </div>
      </header>
      <p class="text-sm text-base-content/60 mb-6">
        {t(@locale, "families.show.members_created", %{
          count: @page.member_count,
          date: DawarichWeb.LocalizedDate.l(@locale, @page.family.created_date, "month_year")
        })}
      </p>
      <DawarichWeb.FamilyGettingStarted.getting_started
        page={@page}
        locale={@locale}
        rails_csrf_token={@rails_csrf_token}
        self_hosted={@self_hosted}
        native={true}
        invitation_email={@invitation_email}
      />
      <div class="flex flex-col lg:flex-row gap-4 min-w-0">
        <div
          id="family-map"
          phx-hook="FamilyMap"
          phx-update="ignore"
          class="w-full lg:w-3/5 min-w-0 min-h-80 rounded-xl border border-base-300 bg-base-200 flex items-center justify-center"
        >
          <div data-family-canvas hidden class="w-full min-h-80"></div>
          <p data-family-empty class="p-4 text-center text-sm text-base-content/60">
            {t(@locale, "families.show.no_family_members_are_sharing_their_location", %{})}
          </p>
        </div>
        <div class="w-full lg:w-2/5 min-w-0 space-y-4">
          <section class="border border-base-300 rounded-xl min-w-0 overflow-hidden">
            <h2 class="bg-base-200 px-4 py-3 font-medium">
              {t(@locale, "families.show.your_sharing", %{})}
            </h2>
            <div class="p-4">
              <FamilyNativeControls.sharing
                member={@page.me}
                locale={@locale}
                now={@now}
                current_scope={@current_scope}
              />
            </div>
          </section>
          <FamilyNativeMembers.members
            page={@page}
            locale={@locale}
            now={@now}
            self_hosted={@self_hosted}
          />
          <FamilyNativeInvitations.invitations
            page={@page}
            locale={@locale}
            now={@now}
            email={@invitation_email}
          />
          <FamilyNativeControls.danger page={@page} locale={@locale} />
        </div>
      </div>
      <FamilyNativeControls.confirmation confirmation={@confirmation} page={@page} locale={@locale} />
    </section>
    """
  end
end
