defmodule DawarichWeb.FamilyNativeMembers do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.FamilyNativeControls

  def members(assigns) do
    ~H"""
    <section class="border border-base-300 rounded-xl min-w-0 overflow-hidden">
      <h3 class="bg-base-200 px-4 py-3 font-medium">
        {s(@locale, "members")} {if @self_hosted,
          do: "(#{length(@page.members)})",
          else: t(@locale, "families.getting_started.seats", %{used: length(@page.members), total: 5})}
      </h3>
      <div
        :for={member <- @page.members}
        data-family-member-id={member.id}
        class="p-4 border-b border-base-200 min-w-0 [overflow-wrap:anywhere]"
      >
        <div class="flex flex-wrap items-center gap-2">
          <span class="font-medium min-w-0">{member.email}</span>
          <span :if={member.role == 0} class="badge badge-warning badge-sm">{s(@locale, "owner")}</span>
          <span :if={member.id == @page.actor_id} class="badge badge-primary badge-sm">{s(
            @locale,
            "you"
          )}</span>
        </div>
        <div class="text-xs text-base-content/60 my-2">
          <%= if member.sharing.enabled? do %>
            <span class="text-success">{s(@locale, "sharing_status", %{
              duration:
                if(member.sharing.duration == "permanent",
                  do: s(@locale, "always"),
                  else: s(@locale, "for_duration", %{duration: member.sharing.duration})
                )
            })}</span>
            <span :if={member.latest_timestamp}>{t(@locale, "common.time_ago", %{
              time:
                DawarichWeb.TimeAgo.words(@locale, DateTime.from_unix!(member.latest_timestamp), @now)
            })}</span>
          <% else %>
            <span>{s(@locale, "not_sharing")}</span>
          <% end %>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            :if={member.id != @page.actor_id and member.sharing.enabled?}
            type="button"
            phx-click="family_focus"
            phx-value-id={member.id}
            class="btn btn-ghost btn-xs h-auto whitespace-normal"
          >{t(@locale, "imports.table_row.view_on_map", %{})}</button>
          <button
            :if={
              member.id != @page.actor_id and !member.sharing.enabled? and
                not is_map_key(@page[:pending_requests] || %{}, member.id)
            }
            type="button"
            phx-click="family_request_location"
            phx-value-target_user_id={member.id}
            class="btn btn-ghost btn-xs h-auto whitespace-normal"
          >{s(@locale, "request")}</button>
          <span
            :if={is_map_key(@page[:pending_requests] || %{}, member.id)}
            class="badge badge-ghost badge-sm h-auto"
          >{s(@locale, "requested")}</span>
          <FamilyNativeControls.confirm_button
            :if={@page.owner? and member.role != 0}
            action="remove_member"
            id={member.membership_id}
            class="btn btn-ghost btn-xs text-error h-auto whitespace-normal"
            label={s(@locale, "remove")}
          />
        </div>
      </div>
    </section>
    """
  end

  defp s(locale, key, bindings \\ %{}), do: t(locale, "families.show." <> key, bindings)
end
