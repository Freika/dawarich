defmodule DawarichWeb.Components.SupporterCard do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.UserSettings

  def card(assigns) do
    assigns =
      assign(assigns,
        email: UserSettings.value(assigns.user, "supporter_email"),
        github: UserSettings.value(assigns.user, "supporter_github_username")
      )

    ~H"""
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body">
        <h2 class="text-2xl font-bold mb-4 flex items-center">
          <.icon name="heart" class="mr-2 text-pink-500" /> {t(
            @locale,
            "settings.general.supporter_status.supporter_status",
            %{}
          )}
        </h2>
        <div class="bg-base-100 p-5 rounded-lg shadow-sm space-y-4">
          <div :if={@supporter} class="alert alert-success">
            <.icon name="circle-check" class="w-5 h-5" />
            <span>{t(@locale, "settings.general.supporter_status.supporter_thanks", %{
              platform: platform(@locale, @platform)
            })}</span>
          </div>
          <form
            data-turbo="false"
            action="/settings/general/verify_supporter"
            accept-charset="UTF-8"
            method="post"
          >
            <input
              :if={@rails_csrf_token}
              type="hidden"
              name="authenticity_token"
              value={@rails_csrf_token}
            />
            <div class="form-control">
              <label class="label" for="supporter_email"><span class="label-text font-medium">{t(
                @locale,
                "settings.general.supporter_status.email_used_for_patreon_github_ko_fi",
                %{}
              )}</span></label>
              <input
                value={@email}
                class="input input-bordered w-full"
                placeholder={
                  t(@locale, "settings.general.supporter_status.supporter_example_com", %{})
                }
                type="email"
                name="supporter_email"
                id="supporter_email"
                phx-update="ignore"
              />
            </div>
            <div class="form-control mt-3">
              <label class="label" for="supporter_github_username"><span class="label-text font-medium">{t(
                @locale,
                "settings.general.supporter_status.github_username_for_github_sponsors_with_a_private_email",
                %{}
              )}</span></label>
              <input
                value={@github}
                class="input input-bordered w-full"
                placeholder={t(@locale, "settings.general.supporter_status.octocat", %{})}
                autocapitalize="none"
                autocorrect="off"
                type="text"
                name="supporter_github_username"
                id="supporter_github_username"
                phx-update="ignore"
              />
            </div>
            <input
              type="submit"
              name="commit"
              value={t(@locale, "settings.general.supporter_status.verify", %{})}
              class="btn btn-primary mt-3"
              data-disable-with={t(@locale, "settings.general.supporter_status.verify", %{})}
            />
          </form>
          <div
            :if={(Ruby.present?(@email) or Ruby.present?(@github)) and not @supporter}
            class="alert"
          >
            <.icon name="triangle-alert" class="w-5 h-5 text-warning" />
            <span>{t(
              @locale,
              "settings.general.supporter_status.not_found_in_supporter_list_make_sure_you_re_using",
              %{}
            )}</span>
          </div>
          <div class="bg-base-200 p-4 rounded-lg space-y-3">
            <h3 class="font-semibold flex items-center gap-2">
              <.icon name="info" class="w-4 h-4 text-primary" /> {t(
                @locale,
                "settings.general.supporter_status.how_to_support_dawarich",
                %{}
              )}
            </h3>
            <p class="text-sm text-base-content/70">
              {t(
                @locale,
                "settings.general.supporter_status.dawarich_is_a_free_and_open_source_project_your_support",
                %{}
              )}
            </p>
            <div class="flex flex-wrap gap-2">
              <a
                href="https://www.patreon.com/freika"
                class="btn btn-sm btn-outline"
                target="_blank"
                rel="noopener noreferrer"
              >{t(@locale, "settings.general.supporter_status.patreon", %{})}</a>
              <a
                href="https://github.com/sponsors/Freika"
                class="btn btn-sm btn-outline"
                target="_blank"
                rel="noopener noreferrer"
              >{t(@locale, "settings.general.supporter_status.github_sponsors", %{})}</a>
              <a
                href="https://ko-fi.com/freika"
                class="btn btn-sm btn-outline"
                target="_blank"
                rel="noopener noreferrer"
              >{t(@locale, "settings.general.supporter_status.ko_fi", %{})}</a>
            </div>
            <h3 class="font-semibold mt-3">
              {t(@locale, "settings.general.supporter_status.supporter_benefits", %{})}
            </h3>
            <ul class="text-sm text-base-content/70 list-disc list-inside space-y-1">
              <li>
                {t(
                  @locale,
                  "settings.general.supporter_status.access_to_reverse_geocoding_api_see_patreon_tier",
                  %{}
                )}
              </li>
              <li>
                {t(@locale, "settings.general.supporter_status.mention_in_github_releases", %{})}
              </li>
              <li>
                {t(
                  @locale,
                  "settings.general.supporter_status.supporter_badge_displayed_in_the_navbar",
                  %{}
                )}
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp platform(_locale, nil), do: ""

  defp platform(locale, platform),
    do:
      t(locale, "settings.general.supporter_status.supporter_platform", %{
        platform: t(locale, "supporter_platforms.#{platform}", %{})
      })
end
