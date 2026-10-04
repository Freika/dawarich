defmodule DawarichWeb.FamilyInvitationDocument do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  def document(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-base-100 to-base-200 py-12 px-4 mx-auto">
      <div class="max-w-4xl mx-auto">
        <div class="text-center mb-12">
          <div class="mx-auto flex items-center justify-center h-24 w-24 rounded-full bg-primary mb-6 shadow-xl">
            <.icon name="users" class="h-12 w-12 text-primary-content" />
          </div>
          <h1 class="text-5xl font-bold text-base-content mb-4">
            {s(@locale, "join")} {@invitation.family_name}!
          </h1>
          <p class="text-xl text-base-content opacity-80 mb-2">
            {s(@locale, "you_ve_been_invited_by")}
            <strong class="text-base-content">{@invitation.invited_by}</strong> {s(
              @locale,
              "to_join_their_family_create_your_account_to_accept_the"
            )}
          </p>
          <div class="alert alert-info inline-flex items-center rounded-lg px-4 py-3 mt-4 gap-3">
            <.icon name="info" class="h-5 w-5 shrink-0" />
            <span class="text-sm font-medium">{s(@locale, "your_email")}{@invitation.email}{s(
              @locale,
              "will_be_used_for_this_account"
            )}</span>
          </div>
        </div>
        <div class="bg-base-200 shadow-xl rounded-2xl p-8 mb-8">
          <h2 class="text-2xl font-bold text-base-content mb-6 text-center">
            {s(@locale, "what_benefits_does_joining_a_family_bring")}
          </h2>
          <div class="grid md:grid-cols-2 gap-6 mb-8">
            <div
              :for={{color, icon, title, body} <- benefits()}
              class={"flex items-start space-x-4 p-4 bg-#{color}/10 rounded-lg border border-#{color}/20"}
            >
              <div class="flex-shrink-0">
                <div class={"h-10 w-10 rounded-full bg-#{color} flex items-center justify-center"}>
                  <.icon name={icon} class={"h-6 w-6 text-#{color}-content"} />
                </div>
              </div>
              <div>
                <h3 class="font-semibold text-base-content mb-1">{s(@locale, title)}</h3>
                <p class="text-sm text-base-content opacity-70">{s(@locale, body)}</p>
              </div>
            </div>
          </div>
          <div class="bg-base-300 rounded-lg p-6 mb-6">
            <h3 class="text-lg font-semibold text-base-content mb-6">
              {s(@locale, "invitation_details")}
            </h3>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div :for={{label, value} <- details(@invitation, @locale)} class="space-y-2">
                <div class="text-sm text-base-content opacity-60">{s(@locale, label)}</div>
                <div class="text-base font-semibold text-base-content">{value}</div>
              </div>
            </div>
          </div>
          <div class="space-y-4">
            <%= cond do %>
              <% !@invitation.plan_active? -> %>
                <div class="alert alert-warning">
                  <.icon name="triangle-alert" class="h-5 w-5 shrink-0" />
                  <span class="text-sm font-medium">{s(
                    @locale,
                    "this_family_s_plan_is_currently_inactive_you_can_accept"
                  )}</span>
                </div>
              <% @current_user != nil -> %>
                <a
                  href={"/family/memberships?token=" <> URI.encode_www_form(@invitation.token)}
                  data-method="post"
                  rel="nofollow"
                  class="btn btn-success btn-lg w-full text-lg shadow-lg"
                >{s(@locale, "accept_invitation_join_family")}</a>
                <p class="text-sm text-base-content opacity-60 text-center">
                  {s(@locale, "logged_in_as")} {@current_user.email} ·
                  <a href="/users/sign_out" data-method="delete" rel="nofollow" class="link link-info">{s(
                    @locale,
                    "logout"
                  )}</a>
                </p>
              <% true -> %>
                <a
                  href={"/users/sign_up?invitation_token=" <> URI.encode_www_form(@invitation.token)}
                  class="btn btn-primary btn-lg w-full text-lg shadow-lg"
                >{s(@locale, "create_account_join_family")}</a>
                <div class="text-center">
                  <p class="text-sm text-gray-300 mb-2">{s(@locale, "already_have_an_account")}</p>
                  <a
                    href={"/users/sign_in?invitation_token=" <> URI.encode_www_form(@invitation.token)}
                    class="link link-info font-medium"
                  >{s(@locale, "sign_in_to_accept_invitation")}</a>
                </div>
            <% end %>
            <div class="pt-6 border-t border-base-300 text-center">
              <p class="text-sm text-base-content opacity-60">
                {s(@locale, "not_interested_you_can_simply_close_this_page")}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "family.invitations.show." <> key, %{})

  defp benefits do
    [
      {"info", "map-pin", "share_location_data",
       "share_your_location_history_with_family_members_and_see_where"},
      {"secondary", "chart-column", "track_your_location_history",
       "access_interactive_maps_and_personal_travel_statistics"},
      {"success", "heart", "stay_connected",
       "keep_track_of_your_loved_ones_travels_and_adventures_in"},
      {"warning", "shield-check", "full_control_privacy",
       "you_control_what_and_how_long_you_share_and_can"}
    ]
  end

  defp details(invitation, locale) do
    [
      {"family", invitation.family_name},
      {"invited_by", invitation.invited_by},
      {"your_email_2", invitation.email},
      {"expires", DawarichWeb.LocalizedDate.l(locale, invitation.expires_date, "medium_padded")}
    ]
  end
end
