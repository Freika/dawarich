defmodule DawarichWeb.SettingsLive.UsersIndex do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.ListParts, only: [page_header: 1]
  alias Dawarich.Admin.UsersPage
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.{AdminUserDialogs, AdminUsersTable, Paginator, SettingsParts}

  @impl true
  def mount(params, _session, socket) do
    case page(params, socket.assigns) do
      {:ok, page} -> {:ok, assign(socket, page)}
      :rails -> {:ok, redirect(socket, to: DawarichWeb.AdminLiveAuth.request_url(socket))}
    end
  end

  def page(params, context) do
    with {:ok, data} <- UsersPage.list(context.current_user, params) do
      {:ok,
       %{
         page_title: t(context.locale, "settings.users.index.users", %{}),
         rails_js: true,
         data: data,
         query: params,
         two_factor: Map.get_lazy(context, :two_factor, &SettingsParts.two_factor_available?/0)
       }}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-content w-full my-5">
      <.page_header title={t(@locale, "settings.users.index.users_management", %{})} />
      <SettingsParts.navigation
        locale={@locale}
        active="users"
        self_hosted={@self_hosted}
        admin={@current_user.admin == true}
        two_factor={@two_factor}
      />
      <div class="w-10/12 mx-auto my-6">
        <div class="card bg-base-200 compact">
          <div class="card-body flex-row items-center justify-between">
            <div>
              <h3 class="font-semibold">
                {t(@locale, "settings.users.index.user_registration", %{})}
              </h3>
              <p class="text-sm text-base-content/70">
                {t(
                  @locale,
                  "settings.users.index.allow_new_users_to_register_via_email_and_password",
                  %{}
                )}
              </p>
            </div>
            <form
              class="flex items-center gap-3"
              data-turbo="false"
              action="/settings/users/update_registration_settings"
              accept-charset="UTF-8"
              method="post"
            >
              <input type="hidden" name="_method" value="patch" /><input
                type="hidden"
                name="authenticity_token"
                value={@rails_csrf_token}
              />
              <input type="hidden" name="registration_enabled" value="0" />
              <input
                type="checkbox"
                name="registration_enabled"
                value="1"
                class="toggle toggle-primary"
                checked={@data.registration && ""}
                onchange="this.form.submit()"
              />
            </form>
          </div>
        </div>
      </div>
      <div class="flex flex-col lg:flex-row w-full my-10 space-x-4">
        <div class="overflow-x-auto w-10/12 mx-auto">
          <div class="flex items-center justify-between mb-4">
            <button class="btn" onclick="create_user.showModal()">{t(
              @locale,
              "settings.users.index.add_new_user",
              %{}
            )}</button>
            <form
              class="flex gap-2"
              data-turbo="false"
              action="/settings/users"
              accept-charset="UTF-8"
              method="get"
            >
              <input
                type="text"
                name="search"
                value={@data.search || ""}
                placeholder={t(@locale, "settings.users.index.search_by_email", %{})}
                class="input input-bordered input-sm w-64"
              />
              <button type="submit" class="btn btn-sm btn-ghost">{t(
                @locale,
                "settings.users.index.search",
                %{}
              )}</button>
              <a :if={Ruby.present?(@data.search)} class="btn btn-sm btn-ghost" href="/settings/users">{t(
                @locale,
                "settings.users.index.clear",
                %{}
              )}</a>
            </form>
          </div>
          <AdminUsersTable.table locale={@locale} rows={@data.rows} actor={@current_user} />
          <div class="mt-4">
            <Paginator.paginator
              locale={@locale}
              path="/settings/users"
              query={@query}
              page={@data.page}
              total_pages={@data.pages}
              patch={false}
            />
          </div>
        </div>
      </div>
    </div>
    <AdminUserDialogs.dialogs
      locale={@locale}
      rows={@data.rows}
      actor={@current_user}
      rails_csrf_token={@rails_csrf_token}
    />
    """
  end
end
