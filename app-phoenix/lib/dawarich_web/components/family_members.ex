defmodule DawarichWeb.FamilyMembers do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]
  alias DawarichWeb.{LocalizedDate, TimeAgo}

  def family_members(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-xl overflow-hidden">
      <div class="bg-base-200 px-4 py-2.5">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          {s(@locale, "members")}
          <span class="text-base-content/30">{if(@self_hosted,
            do: "(#{@page.member_count})",
            else: t(@locale, "families.getting_started.seats", %{used: @page.member_count, total: 5})
          )}</span>
        </h3>
      </div>
      <div class="divide-y divide-base-200">
        <div
          :for={member <- @page.members}
          class="px-4 py-3 hover:bg-base-200/50 transition-colors"
          data-family-member-id={member.id}
        >
          <div class="flex items-center gap-3">
            <div class={"w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 text-sm font-semibold " <> if(member.id == @page.actor_id, do: "bg-primary text-primary-content", else: "bg-base-200 text-base-content/60")}>
              {String.upcase(String.first(member.email) || "?")}
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium truncate">{member.email}</span>
                <span
                  :if={member.role == 0}
                  class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-warning/10 text-warning"
                >{s(@locale, "owner")}</span>
                <span
                  :if={member.id == @page.actor_id}
                  class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-primary/10 text-primary"
                >{s(@locale, "you")}</span>
              </div>
              <div class="flex items-center gap-2 mt-0.5">
                <%= if member.sharing.enabled? do %>
                  <div class="w-2 h-2 bg-success rounded-full animate-pulse"></div>
                  <span class="text-xs text-success">{s(@locale, "sharing_status", %{
                    duration:
                      if(member.sharing.duration == "permanent",
                        do: s(@locale, "always"),
                        else: s(@locale, "for_duration", %{duration: member.sharing.duration})
                      )
                  })}</span>
                  <span
                    hidden={is_nil(member.latest_timestamp)}
                    class="text-xs text-base-content/40"
                    data-family-last-seen={member.id}
                  ><%= if member.latest_timestamp do %>
                    {s(@locale, "middot")} {t(@locale, "common.time_ago", %{
                      time: TimeAgo.words(@locale, DateTime.from_unix!(member.latest_timestamp), @now)
                    })}
                  <% end %></span>
                <% else %>
                  <div class="w-2 h-2 bg-base-300 rounded-full"></div><span class="text-xs text-base-content/40">{s(
                    @locale,
                    "not_sharing"
                  )}</span>
                  <%= if member.id != @page.actor_id do %>
                    <span :if={@page.pending_requests[member.id]} class="text-xs text-info">{s(
                      @locale,
                      "requested"
                    )}</span>
                    <form
                      :if={!@page.pending_requests[member.id]}
                      method="post"
                      action={"/family/location_requests?target_user_id=#{member.id}"}
                      class="button_to"
                    >
                      <button type="submit" class="btn btn-outline btn-xs btn-info ml-auto">{s(
                        @locale,
                        "request"
                      )}</button><input
                        type="hidden"
                        name="authenticity_token"
                        value={@rails_csrf_token}
                      />
                    </form>
                  <% end %>
                <% end %>
              </div>
            </div>
            <a
              :if={@page.owner? and member.id != @page.actor_id and member.role != 0}
              href={"/family/members/#{member.membership_id}"}
              data-turbo-confirm={s(@locale, "remove_email_from_the_family", %{email: member.email})}
              data-turbo-method="delete"
              class="btn btn-ghost btn-xs text-error ml-auto"
            ><.icon name="x" class="w-3.5 h-3.5" /> {s(@locale, "remove")}</a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def family_invitations(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-xl overflow-hidden" id="invite-section">
      <div class="bg-base-200 px-4 py-2.5">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          {s(@locale, "invitations")}
          <span class="text-base-content/30">({@page.pending_count})</span>
        </h3>
      </div>
      <div :if={@page.invitations != []} class="divide-y divide-base-200">
        <div :for={invitation <- @page.invitations} class="px-4 py-3">
          <div class="flex items-center justify-between">
            <div class="min-w-0 flex-1 mr-2">
              <div class="text-sm font-medium">{invitation.email}</div>
              <div class="text-xs text-base-content/40">
                {s(@locale, "invited_ago_expires", %{
                  ago: TimeAgo.words(@locale, invitation.created_at, @now),
                  date:
                    LocalizedDate.l(
                      @locale,
                      NaiveDateTime.to_date(invitation.expires_at),
                      "short_month_day_padded"
                    )
                })}
              </div>
              <div class="text-xs text-base-content/50 font-mono break-all select-all mt-1">
                {@base_url <> "/invitations/" <> invitation.token}
              </div>
            </div>
            <div class="flex items-center gap-1">
              <button
                data-controller="clipboard"
                data-clipboard-text-value={@base_url <> "/invitations/" <> invitation.token}
                data-action="click->clipboard#copy"
                class="btn btn-ghost btn-xs"
              ><.icon name="copy" class="w-3.5 h-3.5" /></button>
              <form
                :if={@page.owner?}
                class="button_to"
                method="post"
                action={"/family/invitations/" <> invitation.token}
                data-turbo-confirm={s(@locale, "cancel_this_invitation")}
                data-turbo-method="delete"
              >
                <input type="hidden" name="_method" value="delete" /><button
                  type="submit"
                  class="btn btn-ghost btn-xs text-error hover:bg-error/10"
                ><.icon name="x" class="w-3.5 h-3.5" /></button><input
                  type="hidden"
                  name="authenticity_token"
                  value={@rails_csrf_token}
                />
              </form>
            </div>
          </div>
        </div>
      </div>
      <div :if={@page.owner? and @page.can_invite?} class="px-4 py-3 border-t border-base-200">
        <.invite_form
          page={@page}
          locale={@locale}
          rails_csrf_token={@rails_csrf_token}
          getting_started={false}
        />
        <p :if={!@self_hosted} class="text-xs text-base-content/50 mt-2">
          {t(@locale, "families.getting_started.members_lose_access_when_your_plan_ends", %{})}
        </p>
      </div>
      <div :if={@page.owner? and !@page.can_invite?} class="px-4 py-3 border-t border-base-200">
        <p class="text-xs text-warning">
          <.icon name="triangle-alert" class="w-3.5 h-3.5 inline" /> {s(
            @locale,
            "family_at_capacity",
            %{count: @page.member_count + @page.pending_count, max: 5}
          )}
        </p>
      </div>
    </div>
    """
  end

  def invite_form(assigns) do
    ~H"""
    <form action={"/family/invitations.#{@page.family.id}"} accept-charset="UTF-8" method="post">
      <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
      <div class={if(@getting_started, do: "flex flex-wrap gap-2", else: "flex gap-2")}>
        <input
          type="email"
          name="family_invitation[email]"
          id="family_invitation_email"
          placeholder={s(@locale, "email_address")}
          class={
            if(@getting_started,
              do: "input input-bordered input-sm flex-1 min-w-0",
              else: "input input-bordered input-sm flex-1"
            )
          }
        />
        <input
          type="submit"
          name="commit"
          value={s(@locale, "invite")}
          class="btn btn-primary btn-sm"
          data-disable-with={s(@locale, "invite")}
        />
      </div>
    </form>
    """
  end

  defp s(locale, key, bindings \\ %{}), do: t(locale, "families.show." <> key, bindings)
end
