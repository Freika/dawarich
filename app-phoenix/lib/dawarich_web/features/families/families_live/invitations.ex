defmodule DawarichWeb.FamiliesLive.Invitations do
  @moduledoc false
  use DawarichWeb, :live_view
  alias DawarichWeb.{FamilyNativeLive, FamilyNativeControls}
  @impl true
  def mount(_, _, socket), do: {:ok, FamilyNativeLive.mount(socket)}
  @impl true
  def handle_event(event, params, socket), do: FamilyNativeLive.event(event, params, socket)
  @impl true
  def handle_info(_, socket), do: {:noreply, socket}
  @impl true
  def handle_params(_, _, socket), do: {:noreply, socket}
  @impl true
  def render(assigns) do
    ~H"""
    <div id="native-family-invitations-shell" class="container mx-auto px-4 py-8">
      <div class="max-w-4xl mx-auto">
        <div class="bg-base-200 rounded-lg p-6">
          <div class="flex items-center justify-between mb-6">
            <h1 class="text-2xl font-bold text-base-content">{s(@locale, "title")}</h1><a
              class="btn btn-neutral"
              href={if @page.live?, do: "/family", else: "/family/new"}
            >{s(@locale, "back_to_family")}</a>
          </div>
          <FamilyNativeControls.errors errors={@errors} />
          <%= if @page.invitations != [] do %>
            <div class="space-y-4">
              <div
                :for={invitation <- @page.invitations}
                class="flex items-center justify-between p-4 bg-base-100 rounded-lg"
                data-native-invitation-id={invitation.id}
              >
                <div>
                  <div class="font-medium text-base-content">{invitation.email}</div><div class="text-sm text-base-content opacity-60">
                    {s(@locale, "invited_on")} {DawarichWeb.LocalizedDate.l(
                      @locale,
                      invitation.created_date,
                      "long"
                    )}
                  </div><div class="text-xs text-base-content opacity-50">
                    {s(@locale, "expires_on")} {DawarichWeb.LocalizedDate.time(
                      @locale,
                      invitation.expires_local,
                      "long_with_time"
                    )}
                  </div>
                </div>
                <div class="flex space-x-2">
                  <button
                    id={"native-invitation-copy-#{invitation.id}"}
                    type="button"
                    phx-hook="FamilyInvitationClipboard"
                    data-native-reveal-path={"/native/family/invitations/#{invitation.id}/copy"}
                    data-native-copied-label={
                      t(@locale, "javascript.messages.copied_to_clipboard", %{})
                    }
                    data-native-failed-label={
                      t(@locale, "javascript.messages.failed_to_copy_please_copy_manually", %{})
                    }
                    class="btn btn-ghost btn-sm text-primary"
                  ><svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-4 w-4 mr-1"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  ><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" /></svg>{s(
                    @locale,
                    "copy_link"
                  )}</button>
                  <a
                    class="btn btn-ghost btn-sm text-info"
                    href={"/native/family/invitations/#{invitation.id}/view"}
                  >{s(@locale, "view_invitation")}</a>
                  <FamilyNativeControls.confirm_button
                    :if={@page.owner?}
                    action="cancel_invitation"
                    id={invitation.id}
                    label={s(@locale, "cancel")}
                    class="btn btn-ghost btn-sm text-error"
                  />
                </div>
              </div>
            </div>
          <% else %>
            <div class="text-center py-8">
              <p class="text-base-content opacity-50 text-lg">{s(@locale, "no_invitations")}</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    <FamilyNativeControls.confirmation confirmation={@confirmation} page={@page} locale={@locale} />
    """
  end

  defp s(locale, key), do: t(locale, "family_invitations.index." <> key, %{})
end
