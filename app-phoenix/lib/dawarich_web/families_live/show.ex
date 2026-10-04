defmodule DawarichWeb.FamiliesLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.FamilyMembers, only: [family_members: 1, family_invitations: 1]

  import DawarichWeb.FamilyControls,
    only: [sharing_toggle: 1, family_danger: 1]

  import DawarichWeb.FamilyGettingStarted, only: [getting_started: 1]

  @impl true
  def mount(_params, _session, socket) do
    case Dawarich.FamilyPage.read(socket.assigns.current_user, :show,
           now: socket.assigns.now,
           self_hosted: socket.assigns.self_hosted
         ) do
      {:ok, page} ->
        {:ok, assign(socket, page: page, page_title: page.family.name, rails_js: true)}

      {:redirect, path, _reason} ->
        {:ok, redirect(socket, to: path)}

      _other ->
        {:ok, redirect(socket, to: "/family")}
    end
  end

  @impl true
  def handle_event("rails_flash", params, socket),
    do: {:noreply, DawarichWeb.RailsWidgets.rails_flash(socket, params)}

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="family-shell"
      class="contents"
      phx-hook="RailsStimulus"
      phx-update="ignore"
      data-turbo="true"
    >
      <div class="w-full my-5">
        <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
          <h1 class="text-3xl font-bold">{@page.family.name}</h1>
          <div class="flex flex-wrap gap-2">
            <div class="flex items-center gap-2">
              <a :if={@page.owner?} href="/family/edit" class="btn btn-outline btn-sm"><DawarichWeb.Icon.icon
                name="square-pen"
                class="w-4 h-4"
              /> {t(@locale, "families.show.edit", %{})}</a>
              <button
                :if={@page.owner? and @page.can_invite?}
                class="btn btn-primary btn-sm"
                onclick="document.getElementById('invite-section').scrollIntoView({behavior:'smooth'})"
              ><DawarichWeb.Icon.icon name="circle-plus" class="w-4 h-4" /> {t(
                @locale,
                "families.show.invite",
                %{}
              )}</button>
            </div>
          </div>
        </div>
        <div class="text-sm text-base-content/50 -mt-4 mb-6">
          {t(@locale, "families.show.members_created", %{
            count: @page.member_count,
            date: DawarichWeb.LocalizedDate.l(@locale, @page.family.created_date, "month_year")
          })}
        </div>
        <.getting_started
          page={@page}
          locale={@locale}
          rails_csrf_token={@rails_csrf_token}
          self_hosted={@self_hosted}
        />
        <div
          id="family-map"
          phx-hook="FamilyPage"
          class="flex flex-col lg:flex-row gap-4"
          style="min-height: 500px;"
          data-controller="family-map"
          data-family-map-locations-value="[]"
          data-family-time-ago={time_ago(@locale)}
        >
          <div class="w-full lg:w-3/5 min-h-full">
            <div
              class="border border-base-300 rounded-xl overflow-hidden h-full relative"
              data-family-map-target="map"
            >
              <div
                data-family-empty
                class="absolute inset-0 flex items-center justify-center bg-base-200 z-10"
              >
                <div class="text-center">
                  <div class="text-base-content/30 mb-2">
                    <DawarichWeb.Icon.icon name="map" class="w-12 h-12 mx-auto" />
                  </div>
                  <p class="text-base-content/50 text-sm">
                    {t(@locale, "families.show.no_family_members_are_sharing_their_location", %{})}
                  </p>
                </div>
              </div>
            </div>
          </div>
          <div class="w-full lg:w-2/5 flex flex-col gap-4">
            <div class="border border-base-300 rounded-xl overflow-hidden">
              <div class="bg-base-200 px-4 py-2.5">
                <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
                  {t(@locale, "families.show.your_sharing", %{})}
                </h3>
              </div>
              <div class="p-4">
                <.sharing_toggle
                  member={@page.me}
                  locale={@locale}
                  now={@now}
                  rails_csrf_token={@rails_csrf_token}
                />
              </div>
            </div>
            <.family_members
              page={@page}
              locale={@locale}
              now={@now}
              self_hosted={@self_hosted}
              rails_csrf_token={@rails_csrf_token}
            />
            <.family_invitations
              page={@page}
              locale={@locale}
              now={@now}
              base_url={@base_url}
              self_hosted={@self_hosted}
              rails_csrf_token={@rails_csrf_token}
            />
            <.family_danger page={@page} locale={@locale} scope="families.show" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp time_ago(locale) do
    scope =
      if locale == "de",
        do: "datetime.distance_in_words.dative",
        else: "datetime.distance_in_words"

    {:ok, words} = Dawarich.I18n.t(locale, scope)

    Jason.encode!(%{
      words: words,
      ago: t(locale, "common.time_ago", %{time: "%{time}"}),
      middot: t(locale, "families.show.middot", %{})
    })
  end
end
