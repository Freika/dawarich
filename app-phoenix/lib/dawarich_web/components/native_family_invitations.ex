defmodule DawarichWeb.NativeFamilyInvitations do
  @moduledoc false
  use DawarichWeb, :html
  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :base_url, :string, required: true
  attr :now, :any, required: true

  def invitations(assigns) do
    ~H"""
    <section
      id="native-family-invitations"
      class="min-w-0 border rounded-xl p-3 [overflow-wrap:anywhere]"
    >
      <h2>{s(@locale, "invitations")} ({@page.pending_count})</h2>
      <div :for={invitation <- @page.invitations} class="min-w-0 flex flex-wrap gap-2 py-2">
        <div class="min-w-0 flex-1">
          <p>{invitation.email}</p>
          <p class="text-xs">
            {s(@locale, "invited_ago_expires", %{
              ago: DawarichWeb.TimeAgo.words(@locale, invitation.created_at, @now),
              date:
                DawarichWeb.LocalizedDate.l(
                  @locale,
                  NaiveDateTime.to_date(invitation.expires_at),
                  "short_month_day_padded"
                )
            })}
          </p>
          <a href={@base_url <> "/invitations/" <> invitation.token} class="link">{@base_url <>
            "/invitations/" <> invitation.token}</a>
        </div>
        <button
          type="button"
          phx-hook="Clipboard"
          id={"family-invite-copy-#{invitation.id}"}
          data-clipboard-text={@base_url <> "/invitations/" <> invitation.token}
          class="btn btn-sm h-auto whitespace-normal"
          aria-label={t(@locale, "shared.sharing_link.copy", %{})}
        >⧉</button>
        <button
          :if={@page.owner?}
          type="button"
          phx-click="family:cancel"
          phx-value-token={invitation.token}
          data-confirm={s(@locale, "cancel_this_invitation")}
          class="btn btn-sm text-error"
        >×</button>
      </div>
      <form
        :if={@page.owner? && @page.can_invite?}
        id="native-family-invite"
        phx-submit="family:invite"
        class="flex flex-wrap min-w-0 gap-2"
      >
        <input
          type="email"
          name="family_invitation[email]"
          maxlength="254"
          required
          placeholder={s(@locale, "email_address")}
          class="input input-bordered min-w-0 flex-1 max-w-full"
          aria-label={s(@locale, "email_address")}
        />
        <button type="submit" class="btn btn-sm h-auto whitespace-normal">{s(@locale, "invite")}</button>
      </form>
      <p :if={@page.owner? && !@page.can_invite?} class="text-warning min-w-0">
        {s(@locale, "family_at_capacity", %{count: @page.member_count + @page.pending_count, max: 5})}
      </p>
    </section>
    """
  end

  defp s(locale, key, bindings \\ %{}), do: t(locale, "families.show." <> key, bindings)
end
