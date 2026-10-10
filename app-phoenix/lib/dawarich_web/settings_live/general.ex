defmodule DawarichWeb.SettingsLive.General do
  @moduledoc false
  use DawarichWeb, :live_view
  use DawarichWeb, :verified_routes

  import DawarichWeb.CoreComponents, only: [input: 1]
  import DawarichWeb.Icon, only: [icon: 1, flag: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.SettingsParts

  alias Dawarich.{Accounts, Settings, Supporters, TimeZoneOptions, UserSettings}
  alias DawarichWeb.SettingsLive.GeneralHelpers

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(page(user, params, socket.assigns))
     |> assign(:form, settings_form(user, socket.assigns.locale))}
  end

  def page(user, _params, %{locale: locale, now: now, self_hosted: self_hosted} = context) do
    supporter =
      Map.get_lazy(context, :supporter, fn ->
        if self_hosted,
          do: Supporters.info(UserSettings.get(user), now),
          else: %{"supporter" => false}
      end)

    %{
      page_title: t(locale, "settings.general.index.general_settings", %{}),
      smtp: Map.get_lazy(context, :smtp, &smtp_configured?/0),
      two_factor: Map.get_lazy(context, :two_factor, &two_factor_available?/0),
      zones: Map.get_lazy(context, :zones, &TimeZoneOptions.list/0),
      supporter: supporter["supporter"] == true,
      platform: supporter["platform"]
    }
  end

  @impl true
  def handle_event("change", params, socket),
    do: {:noreply, assign(socket, :form, to_form(Map.merge(socket.assigns.form.params, params)))}

  def handle_event("save", params, socket) do
    %{current_scope: scope, locale: locale} = socket.assigns

    case Settings.update_general(scope, params) do
      {:ok, %{"locale" => new_locale}} when is_binary(new_locale) and new_locale != locale ->
        {:noreply,
         socket
         |> put_flash(:notice, settings_text(new_locale, "settings_updated"))
         |> redirect(to: ~p"/settings/general")}

      {:ok, _settings} ->
        user = Accounts.get(scope.user.id)

        {:noreply,
         socket
         |> assign(current_user: user, form: settings_form(user, locale))
         |> put_flash(:notice, settings_text(locale, "settings_updated"))}

      {:error, :invalid} ->
        {:noreply, put_flash(socket, :alert, settings_text(locale, "failed_to_update_settings"))}

      {:error, :save_failed} ->
        raise "general settings could not be saved"
    end
  end

  def handle_event("send_test_email", _params, socket) do
    %{current_scope: scope, self_hosted: self_hosted} = socket.assigns
    {kind, message} = Settings.send_test_email(scope, self_hosted: self_hosted)
    {:noreply, put_flash(socket, kind, message)}
  end

  def handle_event("verify_supporter", params, socket) do
    %{current_scope: scope, locale: locale} = socket.assigns

    case Settings.verify_supporter(scope, params) do
      {:ok, %{"supporter" => true} = info} ->
        {:noreply,
         socket
         |> assign(
           current_user: Accounts.get(scope.user.id),
           supporter: true,
           platform: info["platform"]
         )
         |> put_flash(
           :notice,
           settings_text(locale, "verified_thank_you_for_supporting_dawarich_via_platform", %{
             platform: GeneralHelpers.platform_name(info["platform"])
           })
         )}

      {:ok, _} ->
        {:noreply,
         socket
         |> assign(current_user: Accounts.get(scope.user.id), supporter: false, platform: nil)
         |> put_flash(
           :alert,
           settings_text(locale, "not_found_in_supporter_list_make_sure_you_re_using")
         )}

      {:error, :empty} ->
        {:noreply,
         put_flash(
           socket,
           :alert,
           settings_text(locale, "please_enter_an_email_address_or_github_username")
         )}

      {:error, reason} ->
        raise "supporter verification failed: #{inspect(reason)}"
    end
  end

  defp settings_form(user, locale),
    do:
      to_form(%{
        "monthly_digest_emails_enabled" =>
          UserSettings.digest?(user, "monthly_digest_emails_enabled"),
        "yearly_digest_emails_enabled" =>
          UserSettings.digest?(user, "yearly_digest_emails_enabled"),
        "news_emails_enabled" => UserSettings.on_unless_off?(user, "news_emails_enabled"),
        "show_supporter_badge" => UserSettings.on_unless_off?(user, "show_supporter_badge"),
        "timezone" => UserSettings.value(user, "timezone") || System.get_env("TIME_ZONE", "UTC"),
        "locale" => locale
      })

  defp settings_text(locale, key, bindings \\ %{}),
    do: t(locale, "controllers.settings.general." <> key, bindings)

  defp test_email?(assigns),
    do: assigns.smtp and assigns.self_hosted and assigns.current_user.admin == true

  defp flag_code(code), do: GeneralHelpers.flag_code(code)
  defp native_name(code), do: GeneralHelpers.native_name(code)
  defp smtp_link(locale), do: GeneralHelpers.smtp_link(locale)
end
