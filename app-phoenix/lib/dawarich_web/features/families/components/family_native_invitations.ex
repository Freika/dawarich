defmodule DawarichWeb.FamilyNativeInvitations do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.FamilyNativeControls

  def native_form(assigns) do
    assigns = assign_new(assigns, :onboarding, fn -> false end)
    assigns = assign_new(assigns, :email, fn -> "" end)

    assigns =
      assign(
        assigns,
        :prefix,
        if(assigns.onboarding, do: "native-onboarding-invite", else: "native-invite")
      )

    ~H"""
    <form id={@prefix <> "-form"} phx-submit="family_invite" class="space-y-2">
      <label for={@prefix <> "-email"} class="label label-text">{t(
        @locale,
        "families.show.email_address",
        %{}
      )}</label>
      <div class="flex flex-wrap gap-2 min-w-0">
        <input
          id={@prefix <> "-email"}
          name="family_invitation[email]"
          type="email"
          value={@email}
          placeholder={t(@locale, "families.show.email_address", %{})}
          class="input input-bordered input-sm flex-1 min-w-0"
        />
        <button
          type="submit"
          class="btn btn-primary btn-sm h-auto whitespace-normal"
          phx-disable-with={t(@locale, "families.show.invite", %{})}
        >{t(@locale, "families.show.invite", %{})}</button>
      </div>
    </form>
    """
  end

  def invitations(assigns) do
    assigns = assign_new(assigns, :email, fn -> "" end)

    ~H"""
    <section id="invite-section" class="border border-base-300 rounded-xl min-w-0 overflow-hidden">
      <h3 class="bg-base-200 px-4 py-3 font-medium">
        {t(@locale, "families.show.invitations", %{})} ({length(@page.invitations)})
      </h3>
      <div
        :for={invitation <- @page.invitations}
        data-invitation-id={invitation.id}
        class="p-4 border-b border-base-200 min-w-0 [overflow-wrap:anywhere]"
      >
        <div class="font-medium">{invitation.email}</div>
        <div class="text-xs text-base-content/60 my-2">
          {t(@locale, "families.show.invited_ago_expires", %{
            ago: DawarichWeb.TimeAgo.words(@locale, invitation.created_at, @now),
            date:
              DawarichWeb.LocalizedDate.l(
                @locale,
                NaiveDateTime.to_date(invitation.expires_at),
                "short_month_day_padded"
              )
          })}
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <button
            id={"invitation-copy-#{invitation.id}"}
            type="button"
            phx-hook="FamilyInvitationClipboard"
            data-reveal-path={"/native/family/invitations/#{invitation.id}/copy"}
            data-status-id={"invitation-copy-status-#{invitation.id}"}
            data-copied-label={t(@locale, "javascript.messages.copied_to_clipboard", %{})}
            data-failed-label={
              t(@locale, "javascript.messages.failed_to_copy_please_copy_manually", %{})
            }
            class="btn btn-ghost btn-sm h-auto whitespace-normal"
          >{t(@locale, "family_invitations.index.copy_link", %{})}</button>
          <a
            href={"/native/family/invitations/#{invitation.id}/view"}
            class="btn btn-ghost btn-sm h-auto whitespace-normal"
          >{t(@locale, "family_invitations.index.view_invitation", %{})}</a>
          <FamilyNativeControls.confirm_button
            :if={@page.owner?}
            action="cancel_invitation"
            id={invitation.id}
            class="btn btn-ghost btn-sm text-error h-auto whitespace-normal"
            label={t(@locale, "family_invitations.index.cancel", %{})}
          />
        </div>
        <span id={"invitation-copy-status-#{invitation.id}"} aria-live="polite" class="text-xs" />
      </div>
      <div :if={@page.owner? and @page[:can_invite?] == true and @page[:live?] != false} class="p-4">
        <.native_form locale={@locale} email={@email} />
      </div>
      <p :if={@page.invitations == []} class="p-4 text-base-content/60">
        {t(@locale, "family_invitations.index.no_invitations", %{})}
      </p>
      <p :if={@page.owner? and @page[:can_invite?] == false} class="p-4 text-warning">
        {t(@locale, "families.show.family_at_capacity", %{
          count: @page.member_count + @page.pending_count,
          max: 5
        })}
      </p>
    </section>
    """
  end
end
