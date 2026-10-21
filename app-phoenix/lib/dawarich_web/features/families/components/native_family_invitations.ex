defmodule DawarichWeb.NativeFamilyInvitations do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  def invitations(assigns) do
    ~H"""
    <div class="border border-base-300 rounded-xl overflow-hidden" id="invite-section">
      <div class="bg-base-200 px-4 py-2.5">
        <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50">
          {s(@locale, "invitations")}
          <span class="text-base-content/30">({@page.pending_count})</span>
        </h3>
      </div>
      <div
        :if={@page.invitations != []}
        id="native-family-invitations"
        class="divide-y divide-base-200"
      >
        <div :for={invitation <- @page.invitations} class="px-4 py-3">
          <div class="flex items-center justify-between">
            <div class="min-w-0 flex-1 mr-2">
              <div class="text-sm font-medium">{invitation.email}</div>
              <div class="text-xs text-base-content/40">
                {s(@locale, "invited_ago_expires", %{
                  ago: DawarichWeb.TimeAgo.words(@locale, invitation.created_at, @now),
                  date:
                    DawarichWeb.LocalizedDate.l(
                      @locale,
                      NaiveDateTime.to_date(invitation.expires_at),
                      "short_month_day_padded"
                    )
                })}
              </div>
              <div class="text-xs text-base-content/50 font-mono break-all select-all mt-1">
                <a href={"/native/family/invitations/#{invitation.id}/view"}>{t(
                  @locale,
                  "family_invitations.index.view_invitation",
                  %{}
                )}</a>
              </div>
            </div>
            <div class="flex items-center gap-1">
              <button
                id={"native-family-invite-copy-#{invitation.id}"}
                phx-hook="FamilyInvitationClipboard"
                data-native-reveal-path={"/native/family/invitations/#{invitation.id}/copy"}
                data-native-copied-label={t(@locale, "javascript.messages.copied_to_clipboard", %{})}
                data-native-failed-label={
                  t(@locale, "javascript.messages.failed_to_copy_please_copy_manually", %{})
                }
                class="btn btn-ghost btn-xs"
                aria-label={t(@locale, "family_invitations.index.copy_link", %{})}
              ><.icon name="copy" class="w-3.5 h-3.5" /></button>
              <form
                :if={@page.owner?}
                class="button_to"
                method="post"
                action={"/native/family/invitations/#{invitation.id}"}
                phx-submit={Phoenix.LiveView.JS.dispatch("dawarich:family-confirm-prepared")}
              >
                <input type="hidden" name="_method" value="delete" />
                <DawarichWeb.FamilyNativeControls.confirm_button
                  action="cancel_invitation"
                  id={invitation.id}
                  tag="button"
                  label=""
                  locale={@locale}
                  icon="x"
                  class="btn btn-ghost btn-xs text-error hover:bg-error/10"
                />
                <input
                  type="hidden"
                  name="authenticity_token"
                  value={Plug.CSRFProtection.get_csrf_token()}
                />
              </form>
            </div>
          </div>
        </div>
      </div>
      <%= cond do %>
        <% @page.owner? && @page.can_invite? -> %>
          <div class="px-4 py-3 border-t border-base-200">
            <.invite_form locale={@locale} family_id={@page.family.id} /><p
              :if={!@self_hosted}
              class="text-xs text-base-content/50 mt-2"
            >
              {t(@locale, "families.getting_started.members_lose_access_when_your_plan_ends", %{})}
            </p>
          </div>
        <% @page.owner? -> %>
          <div class="px-4 py-3 border-t border-base-200">
            <p class="text-xs text-warning">
              <.icon name="triangle-alert" class="w-3.5 h-3.5 inline" />{s(
                @locale,
                "family_at_capacity",
                %{count: @page.member_count + @page.pending_count, max: 5}
              )}
            </p>
          </div>
        <% true -> %>
      <% end %>
    </div>
    """
  end

  attr :onboarding, :boolean, default: false
  attr :family_id, :integer, default: nil
  attr :locale, :string, required: true

  def invite_form(assigns) do
    prefix = if assigns.onboarding, do: "families.getting_started.", else: "families.show."

    assigns =
      assign(assigns,
        email_label: t(assigns.locale, prefix <> "email_address", %{}),
        invite_label: t(assigns.locale, prefix <> "invite", %{})
      )

    ~H"""
    <form
      id={if @onboarding, do: "native-family-onboarding-invite", else: "native-family-invite"}
      action={"/family/invitations" <> if(@family_id, do: ".#{@family_id}", else: "")}
      accept-charset="UTF-8"
      method="post"
      phx-submit="family:invite"
    >
      <input type="hidden" name="authenticity_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <div class={if @onboarding, do: "flex flex-wrap gap-2", else: "flex gap-2"}>
        <input
          placeholder={@email_label}
          class={"input input-bordered input-sm flex-1" <> if(@onboarding, do: " min-w-0", else: "")}
          type="email"
          name="family_invitation[email]"
          id={if @onboarding, do: "native-family-onboarding-email", else: "family_invitation_email"}
          aria-label={@email_label}
        /><input
          type="submit"
          name="commit"
          value={@invite_label}
          class="btn btn-primary btn-sm"
        />
      </div>
    </form>
    """
  end

  defp s(locale, key, bindings \\ %{}), do: t(locale, "families.show." <> key, bindings)
end
