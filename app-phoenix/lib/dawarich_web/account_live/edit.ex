defmodule DawarichWeb.AccountLive.Edit do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.AccountParts
  import DawarichWeb.ApiKeyParts, only: [api_key: 1]

  alias Dawarich.{Entitlements, Settings, SubscriptionToken, UserData, UserSettings}
  alias Dawarich.Accounts.Scope
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.UserTimeZone
  alias DawarichWeb.AuthAccount.Response
  alias DawarichWeb.DirectUpload

  @max_archive_bytes 50 * 1024 * 1024 * 1024

  @impl true
  def mount(params, session, socket) do
    form = session["account_form"] || %{}

    context =
      Map.merge(socket.assigns, %{
        account_errors: Response.errors(form),
        account_email: form["email"]
      })

    {:ok,
     socket
     |> assign(page(socket.assigns.current_user, params, context))
     |> assign(profile_user: socket.assigns.current_user, checksums: %{})
     |> allow_upload(:archive,
       accept: ~w(.zip application/zip),
       max_entries: 1,
       max_file_size: @max_archive_bytes,
       external: &DirectUpload.presign/2
     )}
  end

  @impl true
  def handle_event("rotate_api_key", _params, socket) do
    user = socket.assigns.current_user

    case Settings.rotate_api_key(
           scope(socket),
           String.slice(user.encrypted_password || "", 0, 29)
         ) do
      {:ok, updated} ->
        {:noreply, assign(socket, :current_user, %{user | api_key: updated.api_key})}

      {:error, :stale_session} ->
        {:noreply, redirect(socket, to: "/users/sign_in")}
    end
  end

  def handle_event("export_data", _params, socket) do
    :ok = UserData.request_export(scope(socket))

    {:noreply,
     socket
     |> put_flash(
       :notice,
       t(
         socket.assigns.locale,
         "controllers.settings.users.your_data_is_being_exported_you_will_receive_a_notification",
         %{}
       )
     )
     |> redirect(to: "/exports")}
  end

  def handle_event("validate_archive", _params, socket), do: {:noreply, socket}

  def handle_event("archive_checksum", %{"ref" => ref, "checksum" => checksum}, socket)
      when is_binary(ref) and is_binary(checksum) do
    refs = Enum.map(socket.assigns.uploads.archive.entries, & &1.ref)

    if ref in refs and checksum =~ ~r/\A[A-Za-z0-9+\/]{22}==\z/,
      do:
        {:noreply, update(socket, :checksums, &(&1 |> Map.take(refs) |> Map.put(ref, checksum)))},
      else: {:noreply, socket}
  end

  def handle_event("cancel_archive", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :archive, ref)}

  def handle_event("import_archive", _params, socket) do
    case uploaded_entries(socket, :archive) do
      {[_ | _], []} ->
        [signed_id] =
          consume_uploaded_entries(socket, :archive, fn %{signed_id: id}, _entry -> {:ok, id} end)

        {kind, key} = import_outcome(UserData.start_import(scope(socket), signed_id))

        {:noreply,
         socket
         |> assign(:checksums, %{})
         |> put_flash(kind, t(socket.assigns.locale, "controllers.settings.users." <> key, %{}))
         |> push_event("close-dialog", %{id: "import_modal"})}

      _ ->
        {:noreply, socket}
    end
  end

  defp import_outcome(:ok), do: {:notice, "your_data_import_has_been_started_you_will_receive_a"}
  defp import_outcome({:error, :blank}), do: {:alert, "please_select_a_zip_archive_to_import"}

  defp import_outcome({:error, :validation}),
    do: {:alert, "failed_to_start_import_please_try_again"}

  defp import_outcome({:error, _}),
    do: {:alert, "an_error_occurred_while_starting_the_import_please_try_again"}

  defp scope(socket), do: Scope.for_user(socket.assigns.current_user, socket.assigns.locale)

  def page(
        user,
        _params,
        %{
          locale: locale,
          now: now,
          self_hosted: _self_hosted
        } = context
      ) do
    trial = user.status == 2
    source_none = user.subscription_source in [nil, 0]

    %{
      page_title: t(locale, "devise.registrations.edit.account", %{}),
      account_errors: Map.get(context, :account_errors, []),
      account_email: Map.get(context, :account_email),
      oauth: provider_name(locale, user.provider),
      trial: trial,
      trial_at:
        trial && user.active_until &&
          UserTimeZone.local(UserSettings.get(user), DateTime.to_naive(user.active_until)),
      auto_converting: trial and Entitlements.future?(user.active_until, now) and not source_none,
      subscription: subscription(user, now),
      points: user.points_count || 0
    }
  end

  defp subscription(%{status: 3}, _now),
    do: "your_signup_isn_t_complete_yet_finish_setting_up_your"

  defp subscription(%{status: 1, active_until: until}, now) do
    if Entitlements.future?(until, now),
      do: "change_plan_update_your_payment_method_or_cancel_your_subscription",
      else: "manage_your_subscription_change_plan_or_update_billing_on_manager"
  end

  defp subscription(_user, _now),
    do: "manage_your_subscription_change_plan_or_update_billing_on_manager"

  defp provider_name(locale, provider) do
    cond do
      not Ruby.present?(provider) -> nil
      provider == "google_oauth2" -> t(locale, "oauth_providers.google", %{})
      provider == "apple" -> t(locale, "oauth_providers.apple", %{})
      provider == "openid_connect" -> System.get_env("OIDC_PROVIDER_NAME", "Openid Connect")
      provider == "github" -> "GitHub"
      true -> Regex.replace(~r/(?:^|_)(.)/, provider, fn _, c -> String.upcase(c) end)
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :manager,
        if(assigns.trial or not assigns.self_hosted,
          do: SubscriptionToken.url(assigns.current_user, assigns.now)
        )
      )

    ~H"""
    <div class="w-full min-w-0 my-5">
      <div class="mx-auto w-full max-w-7xl space-y-6">
        <div>
          <h1 class="text-3xl font-bold sm:text-4xl">
            {t(@locale, "devise.registrations.edit.account_settings", %{})}
          </h1>
        </div>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,24rem)_minmax(0,1fr)] lg:items-start">
          <div class="order-1 space-y-6 lg:sticky lg:top-6">
            <.profile
              locale={@locale}
              user={@profile_user}
              errors={@account_errors}
              submitted_email={@account_email}
              oauth={@oauth}
              rails_csrf_token={@rails_csrf_token}
            />
            <.import_dialog locale={@locale} upload={@uploads.archive} checksums={@checksums} />
          </div>

          <div class="order-2 space-y-6">
            <.plan_cards
              locale={@locale}
              self_hosted={@self_hosted}
              trial={@trial}
              trial_at={@trial_at}
              auto_converting={@auto_converting}
              manager={@manager}
              subscription={@subscription}
              points={@points}
            />

            <div class="card bg-base-100 shadow-xl">
              <div class="card-body p-5 sm:p-6">
                <div class="max-w-3xl">
                  <h2 class="card-title text-2xl">
                    {t(@locale, "devise.registrations.edit.api_access", %{})}
                  </h2>
                  <p class="mt-1 text-sm text-base-content/70">
                    {t(
                      @locale,
                      "devise.registrations.edit.use_your_api_key_for_clients_imports_and_external_integrations",
                      %{}
                    )}
                  </p>
                </div>
                <.api_key locale={@locale} user={@current_user} base_url={@base_url} />
              </div>
            </div>

            <.data_tools
              locale={@locale}
              user={@current_user}
              self_hosted={@self_hosted}
              oauth={@oauth}
              rails_csrf_token={@rails_csrf_token}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
