defmodule DawarichWeb.FamilyNativeControls do
  @moduledoc false
  use DawarichWeb, :html
  alias Phoenix.LiveView.JS

  def errors(assigns) do
    ~H"""
    <div
      :if={@errors != []}
      id="family-errors"
      class="alert alert-error min-w-0 [overflow-wrap:anywhere]"
      role="alert"
    >
      <ul>
        <li :for={error <- @errors}>{error}</li>
      </ul>
    </div>
    """
  end

  def confirm_button(assigns) do
    assigns = assign_new(assigns, :locale, fn -> "en" end)
    assigns = assign_new(assigns, :id, fn -> nil end)
    assigns = assign_new(assigns, :tag, fn -> "a" end)
    assigns = assign_new(assigns, :icon, fn -> nil end)
    assigns = assign_new(assigns, :icon_class, fn -> "w-3.5 h-3.5" end)
    assigns = assign_new(assigns, :class, fn -> "btn btn-outline btn-error" end)
    assigns = assign(assigns, :href, "#")

    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      {[href: @tag == "a" && @href, type: @tag == "button" && "submit"]}
      aria-label={if @label == "", do: t(@locale, "family_invitations.index.cancel", %{})}
      data-native-family-action={@action}
      data-native-family-target={@id}
      class={@class}
      phx-click={
        JS.push("family_prepare_confirm", value: %{action: @action, id: @id})
        |> JS.dispatch("dawarich:open-dialog", to: "#family-confirm")
      }
    >
      <DawarichWeb.Icon.icon :if={@icon} name={@icon} class={@icon_class} /> {@label}
    </.dynamic_tag>
    """
  end

  def confirmation(assigns) do
    ~H"""
    <dialog
      id="family-confirm"
      aria-labelledby="family-confirm-title"
      phx-hook="FamilyConfirm"
      data-pending={to_string(@confirmation != nil)}
      class="modal"
    >
      <div class="modal-box min-w-0 [overflow-wrap:anywhere]">
        <h2 id="family-confirm-title" class="text-xl font-semibold">
          {t(@locale, "javascript.common.confirm", %{})}
        </h2>
        <p class="py-4">{confirm_text(@confirmation, @page, @locale)}</p>
        <div class="modal-action flex-wrap">
          <button
            type="button"
            class="btn h-auto whitespace-normal"
            phx-click={
              JS.push("family_cancel_confirm")
              |> JS.dispatch("dawarich:close-dialog", to: "#family-confirm")
            }
          >{t(@locale, "javascript.common.cancel", %{})}</button>
          <button
            type="button"
            class="btn btn-error h-auto whitespace-normal"
            phx-click="family_confirm"
            phx-disable-with={t(@locale, "javascript.common.confirm", %{})}
          >{t(@locale, "javascript.common.confirm", %{})}</button>
        </div>
      </div>
    </dialog>
    """
  end

  def danger(assigns) do
    ~H"""
    <div :if={@page[:family]} class="flex gap-2 justify-end">
      <.confirm_button
        :if={!@page.owner?}
        action="remove_member"
        id={@page.me.membership_id}
        label={t(@locale, "families.show.leave_family", %{})}
        class="btn btn-ghost btn-xs text-warning"
      />
      <.confirm_button
        :if={@page.owner?}
        action="delete"
        label={t(@locale, "families.show.delete_family", %{})}
        icon="trash-2"
        class="btn btn-ghost btn-xs text-error"
      />
    </div>
    """
  end

  def sharing(assigns) do
    ~H"""
    <DawarichWeb.NativeFamilySharing.toggle
      member={@member}
      locale={@locale}
      now={@now}
      event="family_set_sharing"
    />
    """
  end

  defp confirm_text(nil, _, _), do: ""

  defp confirm_text(%{action: "delete"}, _, locale),
    do: t(locale, "families.show.delete_this_family_this_cannot_be_undone", %{})

  defp confirm_text(%{action: "cancel_invitation"}, _, locale),
    do: t(locale, "families.show.cancel_this_invitation", %{})

  defp confirm_text(%{action: "remove_member", id: id}, %{me: %{membership_id: id}}, locale),
    do: t(locale, "families.show.are_you_sure_you_want_to_leave_this_family", %{})

  defp confirm_text(%{action: "remove_member", id: id}, page, locale) do
    member = Enum.find(page[:members] || [], &(&1.membership_id == id))

    t(locale, "families.show.remove_email_from_the_family", %{
      email: if(member, do: member.email, else: "")
    })
  end
end
