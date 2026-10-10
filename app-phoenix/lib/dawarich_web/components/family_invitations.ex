defmodule DawarichWeb.FamilyInvitations do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.LocalizedDate

  def invitation_index(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <div class="max-w-4xl mx-auto">
        <div class="bg-base-200 rounded-lg p-6">
          <div class="flex items-center justify-between mb-6">
            <h1 class="text-2xl font-bold text-base-content">{s(@locale, "title")}</h1>
            <a
              href={if @self_hosted or @page.live?, do: "/family", else: "/family/new"}
              class="btn btn-neutral"
            >{s(@locale, "back_to_family")}</a>
          </div>
          <%= if @page.invitations != [] do %>
            <div class="space-y-4">
              <div
                :for={invitation <- @page.invitations}
                class="flex items-center justify-between p-4 bg-base-100 rounded-lg"
              >
                <div>
                  <div class="font-medium text-base-content">{invitation.email}</div>
                  <div class="text-sm text-base-content opacity-60">
                    {s(@locale, "invited_on")} {LocalizedDate.l(
                      @locale,
                      invitation.created_date,
                      "long"
                    )}
                  </div>
                  <div class="text-xs text-base-content opacity-50">
                    {s(@locale, "expires_on")} {LocalizedDate.time(
                      @locale,
                      invitation.expires_local,
                      "long_with_time"
                    )}
                  </div>
                </div>
                <div class="flex space-x-2">
                  <button
                    type="button"
                    data-controller="clipboard"
                    data-clipboard-text-value={@base_url <> "/invitations/" <> invitation.token}
                    data-action="click->clipboard#copy"
                    class="btn btn-ghost btn-sm text-primary"
                  >
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="h-4 w-4 mr-1"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    ><path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
                    /></svg>
                    {s(@locale, "copy_link")}
                  </button>
                  <a href={"/invitations/" <> invitation.token} class="btn btn-ghost btn-sm text-info">{s(
                    @locale,
                    "view_invitation"
                  )}</a>
                  <a
                    :if={@page.owner?}
                    href={"/family/invitations/" <> invitation.token}
                    data-turbo-confirm={s(@locale, "cancel_confirm")}
                    data-turbo-method="delete"
                    class="btn btn-ghost btn-sm text-error"
                  >{s(@locale, "cancel")}</a>
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
    """
  end

  defp s(locale, key), do: t(locale, "family_invitations.index." <> key, %{})
end
