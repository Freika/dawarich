defmodule DawarichWeb.FamilyRequestForms do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.TimeAgo

  def location_request(assigns) do
    ~H"""
    <div class="container mx-auto max-w-lg py-8 px-4">
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">{s(@locale, "location_request")}</h2>
          <div class="space-y-4">
            <div>
              <span class="text-sm text-base-content/60">{s(@locale, "requested_by")}</span>
              <p class="text-lg font-medium">{@page.request.requester_email}</p>
            </div>
            <div>
              <span class="text-sm text-base-content/60">{s(@locale, "requested")}</span>
              <p class="text-lg">
                {t(@locale, "common.time_ago", %{
                  time: TimeAgo.words(@locale, @page.request.created_at, @now)
                })}
              </p>
            </div>
            <%= if @page.request.display == :pending do %>
              <div>
                <span class="text-sm text-base-content/60">{s(@locale, "expires")}</span>
                <p class="text-lg">
                  {t(@locale, "common.time_from_now", %{
                    time: TimeAgo.words(@locale, @page.request.expires_at, @now)
                  })}
                </p>
              </div>
              <form
                class="space-y-4 mt-6"
                action={"/family/location_requests/#{@page.request.id}/accept"}
                accept-charset="UTF-8"
                method="post"
              >
                <input type="hidden" name="_method" value="patch" />
                <input
                  type="hidden"
                  name="authenticity_token"
                  value={@rails_csrf_token}
                />
                <div class="form-control">
                  <label class="label"><span class="label-text">{s(@locale, "share_location_for")}</span></label>
                  <select name="duration" class="select select-bordered w-full">
                    <option :for={{value, key} <- durations()} value={value} selected={value == "24h"}>
                      {s(@locale, key)}
                    </option>
                  </select>
                </div>
                <div class="flex gap-3 mt-6">
                  <input
                    type="submit"
                    name="commit"
                    value={s(@locale, "accept_share_location")}
                    class="btn btn-primary flex-1"
                    data-disable-with={s(@locale, "accept_share_location")}
                  />
                </div>
              </form>
              <form
                class="button_to"
                method="post"
                action={"/family/location_requests/#{@page.request.id}/decline"}
              >
                <input type="hidden" name="_method" value="patch" />
                <button class="btn btn-outline btn-warning w-full mt-2" type="submit">{s(
                  @locale,
                  "decline"
                )}</button>
                <input
                  type="hidden"
                  name="authenticity_token"
                  value={@rails_csrf_token}
                />
              </form>
            <% else %>
              <div class="mt-4">
                <div class={"badge badge-#{status_color(@page.request.display)} badge-lg"}>
                  {s(@locale, to_string(@page.request.display))}
                </div>
              </div>
              <div :if={@page.request.responded_at}>
                <span class="text-sm text-base-content/60">{s(@locale, "responded")}</span>
                <p>
                  {t(@locale, "common.time_ago", %{
                    time: TimeAgo.words(@locale, @page.request.responded_at, @now)
                  })}
                </p>
              </div>
            <% end %>
          </div>
          <div class="card-actions justify-end mt-6">
            <a href="/family" class="btn btn-ghost">{s(@locale, "back_to_family")}</a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp s(locale, key), do: t(locale, "family.location_requests.show." <> key, %{})

  defp durations,
    do: [
      {"1h", "hour"},
      {"6h", "hours"},
      {"12h", "hours_2"},
      {"24h", "hours_3"},
      {"permanent", "permanently"}
    ]

  defp status_color(:expired), do: "error"
  defp status_color(:accepted), do: "success"
  defp status_color(:declined), do: "warning"
end
