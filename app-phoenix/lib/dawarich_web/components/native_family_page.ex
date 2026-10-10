defmodule DawarichWeb.NativeFamilyPage do
  @moduledoc false
  use DawarichWeb, :html

  def page(assigns) do
    ~H"""
    <DawarichWeb.NativeMapChrome.header {assigns} />
    <DawarichWeb.Chrome.flash locale={@locale} flash={@flash} native />
    <main :if={@page} id="family-shell" data-native-map-root class="min-w-0 max-w-full w-full p-4">
      <h1 class="text-3xl font-bold [overflow-wrap:anywhere]">{@page.presentation.family.name}</h1>
      <p class="text-sm mb-4">
        {t(@locale, "families.show.members_created", %{
          count: @page.presentation.member_count,
          date:
            DawarichWeb.LocalizedDate.l(@locale, @page.presentation.family.created_date, "month_year")
        })}
      </p>
      <div class="flex flex-col lg:flex-row min-w-0 gap-4">
        <div class="w-full min-w-0 lg:w-3/5 min-h-80">
          <DawarichWeb.FamilyMap.family_map config={@page.config} locale={@locale} />
        </div>
        <div class="w-full min-w-0 lg:w-2/5 space-y-3">
          <a
            :if={@page.presentation.owner?}
            href="/family/edit"
            class="btn btn-sm btn-outline h-auto whitespace-normal"
          >{t(@locale, "families.show.edit", %{})}</a>
          <section id="native-family-members" class="min-w-0 border rounded-xl p-3">
            <h2>{t(@locale, "families.show.members", %{})}</h2>
            <div
              :for={member <- @page.presentation.members}
              data-family-member-id={member.id}
              class="min-w-0 py-3 border-b [overflow-wrap:anywhere]"
            >
              <p>{member.email}</p>
              <span :if={member.role == 0}>{t(@locale, "families.show.owner", %{})}</span>
              <span :if={member.id == @page.presentation.actor_id}>{t(
                @locale,
                "families.show.you",
                %{}
              )}</span>
              <p :if={!member.sharing.enabled?}>{t(@locale, "families.show.not_sharing", %{})}</p>
              <p :if={member.sharing.enabled?}>
                {t(@locale, "families.show.sharing_status", %{
                  duration:
                    if(member.sharing.duration == "permanent",
                      do: t(@locale, "families.show.always", %{}),
                      else:
                        t(@locale, "families.show.for_duration", %{duration: member.sharing.duration})
                    )
                })}
              </p>
              <p :if={member.sharing.enabled? && member.latest_timestamp}>
                {t(@locale, "common.time_ago", %{
                  time:
                    DawarichWeb.TimeAgo.words(
                      @locale,
                      DateTime.from_unix!(member.latest_timestamp),
                      @now
                    )
                })}
              </p>
            </div>
          </section>
        </div>
      </div>
    </main>
    <p :if={@map_error} role="alert">{to_string(@map_error)}</p>
    """
  end
end
