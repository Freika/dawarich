defmodule DawarichWeb.SettingsLive.Integrations do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.IntegrationPanes, only: [service_icon: 1, status_icon: 1, pane: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.SettingsParts, only: [navigation: 1, two_factor_available?: 0]
  alias Dawarich.{Accounts, Entitlements, Integrations, UserSettings}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{StatsFormat, TrekPane}

  @sync_services %{"airtrail" => :airtrail, "teslamate" => :teslamate}
  @secrets ~w(immich_api_key photoprism_api_key airtrail_api_key teslamate_password teslamate_api_token)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       sync_queued: MapSet.new(),
       trek_queued: MapSet.new(),
       trek_created: false,
       trek_form: to_form(%{}, as: :trip_source)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = socket.assigns.current_user

    if params["service"] == "geocoding" and user.admin == true and socket.assigns.self_hosted do
      {:noreply, redirect(socket, to: "/admin/settings")}
    else
      {:noreply, load_page(socket, user, params)}
    end
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{pro_required: true}} = socket)
      when event in ~w(save sync),
      do: {:noreply, failure(socket, :pro_required)}

  def handle_event("change", %{"settings" => params}, socket) do
    values = Map.merge(socket.assigns.form.params, Map.drop(params, @secrets))
    {:noreply, assign(socket, :form, to_form(values, as: :settings))}
  end

  def handle_event("save", %{"settings" => params} = event, socket) do
    case Integrations.update_credentials(
           socket.assigns.current_scope,
           socket.assigns.service,
           params
         ) do
      {:ok, result} ->
        notices =
          if result.success and event["refresh_photos_cache"] not in [nil, false, ""] do
            :ok = Integrations.refresh_photos_cache(socket.assigns.current_scope)

            List.insert_at(
              result.notices,
              1,
              t(socket.assigns.locale, "services.settings.update.photo_cache_refreshed", %{})
            )
          else
            result.notices
          end

        user = Accounts.get(socket.assigns.current_user.id)

        {:noreply,
         socket
         |> load_page(user, %{"service" => socket.assigns.service})
         |> notices(:notice, notices)
         |> notices(:alert, result.alerts)}

      {:error, reason} ->
        {:noreply, failure(socket, reason)}
    end
  end

  def handle_event("sync", _params, %{assigns: %{service: service}} = socket)
      when service in ~w(airtrail teslamate) do
    if MapSet.member?(socket.assigns.sync_queued, service) do
      {:noreply, socket}
    else
      case Integrations.start_sync(
             socket.assigns.current_scope,
             Map.fetch!(@sync_services, service)
           ) do
        {:ok, :queued} ->
          {:noreply,
           socket
           |> assign(:sync_queued, MapSet.put(socket.assigns.sync_queued, service))
           |> put_flash(
             :notice,
             t(
               socket.assigns.locale,
               "controllers.settings.background_jobs.job_was_successfully_created",
               %{}
             )
           )}

        {:error, reason} ->
          {:noreply, failure(socket, reason)}
      end
    end
  end

  def handle_event("sync", _params, socket), do: {:noreply, socket}

  def handle_event("trek-create", _params, %{assigns: %{trek_created: true}} = socket),
    do: {:noreply, socket}

  def handle_event("trek-create", %{"trip_source" => params}, socket) do
    case Dawarich.Integrations.Trek.create_source(socket.assigns.current_scope, params) do
      {:ok, id} ->
        {:noreply,
         socket
         |> assign(:trek_created, true)
         |> trek_notice(:notice, "create.connected_choose_trips")
         |> push_navigate(to: "/settings/trek_sources/#{id}/select_trips")}

      {:error, reason} ->
        {:noreply, trek_failure(socket, reason)}
    end
  end

  def handle_event("trek-sync", %{"id" => id}, socket) do
    if MapSet.member?(socket.assigns.trek_queued, id) do
      {:noreply, socket}
    else
      case Dawarich.Integrations.Trek.sync_source(socket.assigns.current_scope, id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:trek_queued, MapSet.put(socket.assigns.trek_queued, id))
           |> trek_notice(:notice, "sync.sync_queued")}

        {:error, reason} ->
          {:noreply, trek_failure(socket, reason)}
      end
    end
  end

  def handle_event("trek-delete", %{"id" => id}, socket) do
    case Dawarich.Integrations.Trek.delete_source(socket.assigns.current_scope, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:sources, Integrations.trek_sources(socket.assigns.current_user))
         |> trek_notice(:notice, "destroy.source_removed_trips_kept")}

      {:error, reason} ->
        {:noreply, trek_failure(socket, reason)}
    end
  end

  defp trek_notice(socket, kind, key),
    do: put_flash(socket, kind, t(socket.assigns.locale, "settings.trek_sources." <> key, %{}))

  defp trek_failure(socket, :importing), do: trek_notice(socket, :alert, "sync.source_importing")
  defp trek_failure(socket, :disabled), do: trek_notice(socket, :alert, "sync.source_disabled")
  defp trek_failure(socket, %{message: message}), do: put_flash(socket, :alert, message)

  defp trek_failure(socket, message) when is_binary(message),
    do: put_flash(socket, :alert, message)

  defp trek_failure(socket, reason), do: failure(socket, reason)

  defp load_page(socket, user, params) do
    page = page(user, params, socket.assigns)

    values =
      UserSettings.get(user)
      |> Map.filter(fn {key, _} ->
        Enum.any?(~w(immich photoprism airtrail teslamate), &String.starts_with?(key, &1 <> "_"))
      end)
      |> mask()

    socket
    |> assign(page)
    |> assign(:current_user, user)
    |> assign(:form, to_form(values, as: :settings))
    |> assign(
      :upgrade,
      page.pro_required &&
        StatsFormat.upgrade_url(
          user,
          socket.assigns.now,
          socket.assigns.self_hosted,
          "settings",
          "integrations"
        )
    )
  end

  defp mask(settings),
    do:
      Map.new(settings, fn {key, value} ->
        {key, if(key in @secrets and Ruby.present?(value), do: "********", else: value)}
      end)

  defp notices(socket, _kind, []), do: socket
  defp notices(socket, kind, messages), do: put_flash(socket, kind, Enum.join(messages, ". "))

  defp failure(socket, :inactive),
    do:
      socket
      |> put_flash(
        :notice,
        t(socket.assigns.locale, "controllers.application.your_account_is_not_active", %{})
      )
      |> redirect(to: "/")

  defp failure(socket, :pro_required),
    do:
      put_flash(
        socket,
        :alert,
        t(socket.assigns.locale, "controllers.application.this_feature_requires_a_pro_plan", %{})
      )

  defp failure(socket, _),
    do:
      put_flash(
        socket,
        :alert,
        t(socket.assigns.locale, "controllers.settings.failed_to_update_settings", %{})
      )

  def page(user, params, %{locale: locale, now: now, self_hosted: self_hosted} = context) do
    page = %{
      page_title: t(locale, "settings.integrations.index.settings", %{}),
      rails_js: false,
      two_factor: Map.get_lazy(context, :two_factor, &two_factor_available?/0),
      pro_required: not Entitlements.full_access?(user, self_hosted, now)
    }

    if page.pro_required do
      page
    else
      service = Integrations.service(params["service"])
      sources = Integrations.trek_sources(user)

      Map.merge(page, %{
        service: service,
        statuses: Integrations.statuses(user, sources),
        sources: if(service == "trek", do: sources, else: []),
        synced:
          if(service in ~w(airtrail teslamate),
            do: Integrations.synced_text(locale, user, service <> "_last_synced_at")
          )
      })
    end
  end
end
