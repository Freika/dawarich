defmodule DawarichWeb.FamilyNativeRequests do
  @moduledoc false
  use DawarichWeb, :html

  def request(assigns) do
    ~H"""
    <div id="native-family-request-shell" class="container mx-auto max-w-lg py-8 px-4">
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">{s(@locale, "location_request")}</h2>
          <DawarichWeb.FamilyNativeControls.errors errors={@errors} />
          <div class="space-y-4">
            <div>
              <span class="text-sm text-base-content/60">{s(@locale, "requested_by")}</span><p class="text-lg font-medium">
                {@page.request.requester_email}
              </p>
            </div>
            <div>
              <span class="text-sm text-base-content/60">{s(@locale, "requested")}</span><p class="text-lg">
                {t(@locale, "common.time_ago", %{
                  time: DawarichWeb.TimeAgo.words(@locale, @page.request.created_at, @now)
                })}
              </p>
            </div>
            <%= if @page.request.display == :pending do %>
              <div>
                <span class="text-sm text-base-content/60">{s(@locale, "expires")}</span><p class="text-lg">
                  {t(@locale, "common.time_from_now", %{
                    time: DawarichWeb.TimeAgo.words(@locale, @page.request.expires_at, @now)
                  })}
                </p>
              </div>
              <form
                id="native-family-request"
                class="space-y-4 mt-6"
                action={"/family/location_requests/#{@page.request.id}/accept"}
                accept-charset="UTF-8"
                method="post"
                phx-submit={Phoenix.LiveView.JS.push("family_respond", value: %{decision: "accept"})}
              >
                <input type="hidden" name="_method" value="patch" /><input
                  type="hidden"
                  name="authenticity_token"
                  value={@rails_csrf_token}
                />
                <div class="form-control">
                  <label class="label"><span class="label-text">{s(@locale, "share_location_for")}</span></label><select
                    name="duration"
                    class="select select-bordered w-full"
                    aria-label={s(@locale, "share_location_for")}
                  ><option :for={{value, key} <- durations()} value={value} selected={value == "24h"}>
                    {s(@locale, key)}
                  </option></select>
                </div>
                <div class="flex gap-3 mt-6">
                  <input
                    type="submit"
                    name="commit"
                    value={s(@locale, "accept_share_location")}
                    class="btn btn-primary flex-1"
                    phx-disable-with={s(@locale, "accept_share_location")}
                  />
                </div>
              </form>
              <form
                class="button_to"
                method="post"
                action={"/family/location_requests/#{@page.request.id}/decline"}
                phx-submit={Phoenix.LiveView.JS.push("family_respond", value: %{decision: "decline"})}
              >
                <input type="hidden" name="_method" value="patch" /><button
                  class="btn btn-outline btn-warning w-full mt-2"
                  type="submit"
                >{s(@locale, "decline")}</button><input
                  type="hidden"
                  name="authenticity_token"
                  value={@rails_csrf_token}
                />
              </form>
            <% else %>
              <div class="mt-4">
                <div
                  data-request-status={@page.request.display}
                  class={"badge badge-#{status_class(@page.request.display)} badge-lg"}
                >
                  {s(@locale, to_string(@page.request.display))}
                </div>
              </div>
              <div :if={@page.request.responded_at}>
                <span class="text-sm text-base-content/60">{s(@locale, "responded")}</span><p>
                  {t(@locale, "common.time_ago", %{
                    time: DawarichWeb.TimeAgo.words(@locale, @page.request.responded_at, @now)
                  })}
                </p>
              </div>
            <% end %>
          </div>
          <div class="card-actions justify-end mt-6">
            <a class="btn btn-ghost" href="/family">{s(@locale, "back_to_family")}</a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_class(:expired), do: "error"
  defp status_class(:accepted), do: "success"
  defp status_class(_), do: "warning"
  defp s(locale, key), do: t(locale, "family.location_requests.show." <> key, %{})

  defp durations,
    do: [
      {"1h", "hour"},
      {"6h", "hours"},
      {"12h", "hours_2"},
      {"24h", "hours_3"},
      {"permanent", "permanently"}
    ]
end
