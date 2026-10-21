defmodule DawarichWeb.NativeFamilyLapsed do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.FamilyNativeControls

  def lapsed(assigns) do
    ~H"""
    <div class="text-center mb-8">
      <h1 class="text-3xl font-bold text-base-content mb-4">
        {s(@locale, "family_plan_no_longer_active")}
      </h1>
      <p class="text-base-content opacity-60">
        {s(
          @locale,
          if(@page.owner?,
            do: "your_family_plan_is_no_longer_active_so_family_features",
            else: "your_family_s_plan_is_no_longer_active_so_family"
          )
        )}
      </p>
    </div>
    <div class="bg-base-200 rounded-lg p-6">
      <%= if @page.owner? do %>
        <div class="text-center mb-6">
          <a
            href="/native/family/upgrade"
            target="_blank"
            rel="noopener noreferrer"
            class="btn btn-primary"
          >{s(@locale, "renew_family_plan")}</a>
        </div>
        <div :if={@page[:invitations] != []} class="text-center mb-6">
          <a class="link text-sm" href="/family/invitations">{s(@locale, "view_pending_invitations")}</a>
        </div>
        <div :if={Enum.any?(@page.members, &(&1.id != @page.actor_id))} class="mb-6">
          <h2 class="text-sm font-medium mb-2">{s(@locale, "members")}</h2><ul class="space-y-2">
            <li
              :for={member <- @page.members}
              :if={member.id != @page.actor_id}
              class="flex items-center justify-between"
            >
              <span class="text-sm">{member.email}</span><FamilyNativeControls.confirm_button
                action="remove_member"
                id={member.membership_id}
                label={s(@locale, "remove")}
                class="btn btn-ghost btn-xs text-warning"
              />
            </li>
          </ul>
        </div>
      <% end %>
      <div class="mb-6">
        <h2 class="text-sm font-medium mb-2">{s(@locale, "your_location_sharing")}</h2><FamilyNativeControls.sharing
          member={@page.me}
          locale={@locale}
          now={@now}
          current_scope={@current_scope}
        />
      </div>
      <div class="flex gap-2 justify-end">
        <FamilyNativeControls.confirm_button
          :if={@page.owner?}
          action="delete"
          label={s(@locale, "delete_family")}
          icon="trash-2"
          class="btn btn-ghost btn-xs text-error"
        />
        <FamilyNativeControls.confirm_button
          :if={!@page.owner?}
          action="remove_member"
          id={@page.me.membership_id}
          label={s(@locale, "leave_family")}
          class="btn btn-ghost btn-xs text-warning"
        />
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "families.lapsed." <> key, %{})
end
