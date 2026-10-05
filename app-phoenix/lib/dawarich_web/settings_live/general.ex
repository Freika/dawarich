defmodule DawarichWeb.SettingsLive.General do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.Icon, only: [icon: 1, flag: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.SettingsParts

  alias Dawarich.{Supporters, TimeZoneOptions, UserSettings}
  alias DawarichWeb.SettingsLive.GeneralHelpers

  @impl true
  def mount(params, _session, socket),
    do: {:ok, assign(socket, page(socket.assigns.current_user, params, socket.assigns))}

  def page(user, _params, %{locale: locale, now: now, self_hosted: self_hosted} = context) do
    supporter =
      Map.get_lazy(context, :supporter, fn ->
        if self_hosted,
          do: Supporters.info(UserSettings.get(user), now),
          else: %{"supporter" => false}
      end)

    %{
      page_title: t(locale, "settings.general.index.general_settings", %{}),
      morph_page_refreshes: true,
      rails_js: true,
      smtp: Map.get_lazy(context, :smtp, &smtp_configured?/0),
      two_factor: Map.get_lazy(context, :two_factor, &two_factor_available?/0),
      zones: Map.get_lazy(context, :zones, &TimeZoneOptions.list/0),
      supporter: supporter["supporter"] == true,
      platform: supporter["platform"]
    }
  end

  defp zone(user), do: UserSettings.value(user, "timezone") || System.get_env("TIME_ZONE", "UTC")

  defp flag_code(code), do: GeneralHelpers.flag_code(code)
  defp native_name(code), do: GeneralHelpers.native_name(code)
  defp smtp_link(locale), do: GeneralHelpers.smtp_link(locale)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-content w-full my-5">
      <.page_header title={t(@locale, "settings.general.index.general_settings", %{})} />
      <.navigation
        locale={@locale}
        active="general"
        self_hosted={@self_hosted}
        admin={@current_user.admin == true}
        two_factor={@two_factor}
      />

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div class="card bg-base-200 shadow-xl">
          <form data-turbo="false" action="/settings/general" accept-charset="UTF-8" method="post">
            <input type="hidden" name="_method" value="patch" />
            <input
              :if={@rails_csrf_token}
              type="hidden"
              name="authenticity_token"
              value={@rails_csrf_token}
            />
            <div class="card-body">
              <div class="space-y-8 animate-fade-in">
                <div id="email-digests">
                  <h2 class="text-2xl font-bold mb-4 flex items-center">
                    <.icon name="mail" class="text-primary mr-2" /> {t(
                      @locale,
                      "settings.general.index.email_preferences",
                      %{}
                    )}
                  </h2>
                  <div :if={@smtp} class="bg-base-100 p-5 rounded-lg shadow-sm space-y-4">
                    <.toggle
                      name="monthly_digest_emails_enabled"
                      checked={UserSettings.digest?(@current_user, "monthly_digest_emails_enabled")}
                      label={t(@locale, "settings.general.index.monthly_digest_emails", %{})}
                      hint={
                        t(
                          @locale,
                          "settings.general.index.summary_of_your_last_month_sent_on_the_2nd",
                          %{}
                        )
                      }
                    />
                    <.toggle
                      name="yearly_digest_emails_enabled"
                      checked={UserSettings.digest?(@current_user, "yearly_digest_emails_enabled")}
                      label={t(@locale, "settings.general.index.year_end_digest_emails", %{})}
                      hint={
                        t(
                          @locale,
                          "settings.general.index.receive_an_annual_summary_on_january_2nd_with_your_year",
                          %{}
                        )
                      }
                    />
                    <.toggle
                      name="news_emails_enabled"
                      checked={UserSettings.on_unless_off?(@current_user, "news_emails_enabled")}
                      label={t(@locale, "settings.general.index.news_updates", %{})}
                      hint={
                        t(
                          @locale,
                          "settings.general.index.receive_occasional_emails_about_new_features_and_important_updates",
                          %{}
                        )
                      }
                    />
                    <div :if={@self_hosted} class="border-t border-base-content/10 pt-4">
                      <div class="flex flex-wrap items-center gap-3">
                        <a
                          data-turbo="true"
                          data-turbo-method="post"
                          class="btn btn-outline btn-sm"
                          href="/settings/general/test_email"
                        >{t(@locale, "settings.general.index.send_test_email", %{})}</a>
                        <span class="text-sm text-base-content/70">{t(
                          @locale,
                          "settings.general.index.test_email_worker_hint",
                          %{}
                        )}</span>
                      </div>
                    </div>
                  </div>
                  <div :if={!@smtp} class="bg-base-100 p-5 rounded-lg shadow-sm">
                    <p class="text-sm text-base-content/70">
                      {t(@locale, "controllers.settings.general.smtp_not_configured_html", %{
                        link: smtp_link(@locale)
                      })}
                    </p>
                  </div>
                </div>

                <div>
                  <h2 class="text-2xl font-bold mb-4 flex items-center">
                    <.icon name="globe" class="text-primary mr-2" /> {t(
                      @locale,
                      "settings.general.index.language",
                      %{}
                    )}
                  </h2>
                  <div class="bg-base-100 p-5 rounded-lg shadow-sm space-y-4">
                    <div class="form-control">
                      <label class="label">
                        <span class="label-text font-medium">{t(
                          @locale,
                          "settings.general.index.your_language",
                          %{}
                        )}</span>
                      </label>
                      <div
                        class="grid grid-cols-1 sm:grid-cols-2 gap-3"
                        role="radiogroup"
                        aria-label={t(@locale, "settings.general.index.your_language", %{})}
                      >
                        <label
                          :for={code <- DawarichWeb.Locale.locales()}
                          class="cursor-pointer"
                          data-testid="language-choice"
                        >
                          <input
                            class="peer sr-only"
                            type="radio"
                            value={code}
                            checked={code == @locale && "checked"}
                            name="locale"
                            id={"locale_" <> code}
                            phx-update="ignore"
                          />
                          <div class="flex items-center gap-3 rounded-lg border-2 border-base-300 p-3 transition-colors hover:border-base-content/30 peer-checked:border-primary peer-checked:bg-primary/10 peer-focus-visible:ring-2 peer-focus-visible:ring-primary">
                            <.flag
                              code={flag_code(code)}
                              class="inline-block rounded-sm h-5 w-auto shadow-sm shrink-0"
                            />
                            <span class="font-medium truncate" lang={code} data-testid="language-name">{native_name(
                              code
                            )}</span>
                          </div>
                        </label>
                      </div>
                      <p class="text-sm text-base-content/70 mt-3">
                        {t(
                          @locale,
                          "settings.general.index.the_interface_emails_and_notifications_will_use_this_language",
                          %{}
                        )}
                      </p>
                    </div>
                  </div>
                </div>

                <div>
                  <h2 class="text-2xl font-bold mb-4 flex items-center">
                    <.icon name="clock" class="text-primary mr-2" /> {t(
                      @locale,
                      "settings.general.index.timezone",
                      %{}
                    )}
                  </h2>
                  <div class="bg-base-100 p-5 rounded-lg shadow-sm space-y-4">
                    <div class="form-control">
                      <label class="label">
                        <span class="label-text font-medium">{t(
                          @locale,
                          "settings.general.index.your_timezone",
                          %{}
                        )}</span>
                      </label>
                      <select
                        class="select select-bordered w-full"
                        name="timezone"
                        id="timezone"
                        phx-update="ignore"
                      >
                        <option
                          :for={{label, iana} <- @zones}
                          selected={iana == zone(@current_user) && "selected"}
                          value={iana}
                        >
                          {label}
                        </option>
                      </select>
                      <p class="text-sm text-base-content/70 mt-1">
                        {t(
                          @locale,
                          "settings.general.index.all_dates_and_times_will_be_displayed_in_this_timezone",
                          %{}
                        )}
                      </p>
                    </div>
                  </div>
                </div>

                <div :if={@self_hosted and @supporter}>
                  <h2 class="text-2xl font-bold mb-4 flex items-center">
                    <.icon name="gem" class="mr-2 text-sky-400" /> {t(
                      @locale,
                      "settings.general.index.supporter_badge",
                      %{}
                    )}
                  </h2>
                  <div class="bg-base-100 p-5 rounded-lg shadow-sm space-y-4">
                    <.toggle
                      name="show_supporter_badge"
                      checked={UserSettings.on_unless_off?(@current_user, "show_supporter_badge")}
                      label={t(@locale, "settings.general.index.show_supporter_badge_in_navbar", %{})}
                      hint={
                        t(
                          @locale,
                          "settings.general.index.display_a_gem_icon_next_to_your_profile_to_show",
                          %{}
                        )
                      }
                    />
                  </div>
                </div>
              </div>
              <div class="card-actions justify-end mt-6">
                <input
                  type="submit"
                  name="commit"
                  value={t(@locale, "settings.general.index.save_changes", %{})}
                  class="btn btn-primary"
                  data-disable-with={t(@locale, "settings.general.index.save_changes", %{})}
                />
              </div>
            </div>
          </form>
        </div>

        <.supporter_card
          :if={@self_hosted}
          locale={@locale}
          user={@current_user}
          supporter={@supporter}
          platform={@platform}
          rails_csrf_token={@rails_csrf_token}
        />
        <.consent_card
          :if={@self_hosted}
          locale={@locale}
          granted={@current_user.changelog_consent == 1}
          rails_csrf_token={@rails_csrf_token}
        />
      </div>
    </div>
    """
  end
end
