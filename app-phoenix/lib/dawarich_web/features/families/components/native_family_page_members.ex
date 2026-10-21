defmodule DawarichWeb.NativeFamilyPageMembers do
  @moduledoc false
  use DawarichWeb, :html

  def members(assigns) do
    ~H"""
    <div id="native-family-members" class="border border-base-300 rounded-xl overflow-hidden">
      <div class="bg-base-200 px-4 py-2.5">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          {s(@locale, "members")}
          <span class="text-base-content/30">{if @self_hosted,
            do: "(#{@page.member_count})",
            else: t(@locale, "families.getting_started.seats", %{used: @page.member_count, total: 5})}</span>
        </h3>
      </div>
      <div class="divide-y divide-base-200">
        <div
          :for={member <- @page.members}
          data-native-family-member-id={member.id}
          class={"px-4 py-3 hover:bg-base-200/50 transition-colors" <> if(member.sharing.enabled? && member.latest_timestamp, do: " cursor-pointer", else: "")}
        >
          <div class="flex items-center gap-3">
            <div class={"w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 text-sm font-semibold " <> if(member.id == @page.actor_id, do: "bg-primary text-primary-content", else: "bg-base-200 text-base-content/60")}>
              {initial(member.email)}
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
                  <div class="w-2 h-2 bg-success rounded-full animate-pulse"></div><span class="text-xs text-success">{s(
                    @locale,
                    "sharing_status",
                    %{
                      duration:
                        if(member.sharing.duration == "permanent",
                          do: s(@locale, "always"),
                          else: s(@locale, "for_duration", %{duration: member.sharing.duration})
                        )
                    }
                  )}</span>
                  <span
                    :if={member.latest_timestamp}
                    class="text-xs text-base-content/40"
                    data-testid="family-last-seen"
                  >{s(@locale, "middot")} {t(@locale, "common.time_ago", %{
                    time:
                      DawarichWeb.TimeAgo.words(
                        @locale,
                        DateTime.from_unix!(member.latest_timestamp),
                        @now
                      )
                  })}</span>
                <% else %>
                  <div class="w-2 h-2 bg-base-300 rounded-full"></div><span class="text-xs text-base-content/40">{s(
                    @locale,
                    "not_sharing"
                  )}</span>
                  <%= if member.id != @page.actor_id do %>
                    <%= if @page.pending_requests[member.id] do %>
                      <span class="text-xs text-info">{s(@locale, "requested")}</span>
                    <% else %>
                      <form
                        class="button_to"
                        method="post"
                        action={"/family/location_requests?target_user_id=#{member.id}"}
                        phx-submit={
                          Phoenix.LiveView.JS.push("family:request",
                            value: %{id: Integer.to_string(member.id)}
                          )
                        }
                      >
                        <button class="btn btn-outline btn-xs btn-info ml-auto" type="submit">{s(
                          @locale,
                          "request"
                        )}</button><input
                          type="hidden"
                          name="authenticity_token"
                          value={Plug.CSRFProtection.get_csrf_token()}
                        />
                      </form>
                    <% end %>
                  <% end %>
                <% end %>
              </div>
            </div>
            <DawarichWeb.FamilyNativeControls.confirm_button
              :if={@page.owner? && member.id != @page.actor_id && member.role != 0}
              action="remove_member"
              id={member.membership_id}
              label={s(@locale, "remove")}
              icon="x"
              class="btn btn-ghost btn-xs text-error ml-auto"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp initial(email) when is_binary(email) and email != "",
    do: email |> String.first() |> String.upcase()

  defp initial(_), do: "?"

  defp s(locale, key, bindings \\ %{}), do: t(locale, "families.show." <> key, bindings)
end
