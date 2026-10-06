defmodule DawarichWeb.SettingsLive.UserEdit do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Admin.UsersPage
  alias DawarichWeb.SettingsParts
  @statuses ~w(inactive active trial pending_payment)

  @impl true
  def mount(params, _session, socket) do
    case page(params, socket.assigns) do
      {:ok, page} -> {:ok, assign(socket, page)}
      :rails -> {:ok, redirect(socket, to: DawarichWeb.AdminLiveAuth.request_url(socket))}
    end
  end

  def page(%{"id" => id}, context) do
    with {id, ""} <- Integer.parse(id),
         {:ok, target} <- UsersPage.find(context.current_user, id, :edit) do
      {:ok,
       %{
         page_title: label(context.locale, "editing_user"),
         rails_js: true,
         target: target,
         two_factor: Map.get_lazy(context, :two_factor, &SettingsParts.two_factor_available?/0)
       }}
    else
      _ -> :rails
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :statuses, Enum.with_index(@statuses))

    ~H"""
    <div class="min-h-content w-full">
      <SettingsParts.navigation
        locale={@locale}
        active="users"
        self_hosted={@self_hosted}
        admin={@current_user.admin == true}
        two_factor={@two_factor}
      />
      <div class="flex w-full my-10 space-x-4">
        <div class="overflow-x-auto w-4/12 mx-auto">
          <h1 class="text-2xl font-bold">{label(@locale, "editing_user")}</h1>
          <p class="text-base-content/70 mb-4">{@target.email}</p>
          <form
            data-turbo-method="put"
            data-turbo="false"
            class="edit_user"
            id={"edit_user_#{@target.id}"}
            phx-update="ignore"
            action={"/settings/users/#{@target.id}"}
            accept-charset="UTF-8"
            method="post"
          >
            <input type="hidden" name="_method" value="put" /><input
              type="hidden"
              name="authenticity_token"
              value={@rails_csrf_token}
            />
            <div class="form-control">
              <label for="user_email">{label(@locale, "email")}</label><input
                value={@target.email}
                class="input input-bordered"
                type="email"
                name="user[email]"
                id="user_email"
              />
            </div>
            <div class="form-control mt-4">
              <label for="user_password">{label(@locale, "password")}
              <span class="text-base-content/50 text-sm">{label(
                @locale,
                "leave_blank_to_keep_current"
              )}</span></label>
              <input
                autocomplete="new-password"
                class="input input-bordered"
                type="password"
                name="user[password]"
                id="user_password"
              />
            </div>
            <div class="form-control mt-4">
              <label class="label cursor-pointer justify-start gap-4">
                <input name="user[admin]" type="hidden" value="0" /><input
                  class="toggle toggle-primary"
                  type="checkbox"
                  value="1"
                  checked={@target.admin && "checked"}
                  name="user[admin]"
                  id="user_admin"
                />
                <span class="label-text">{label(@locale, "admin")}</span>
              </label>
            </div>
            <div class="form-control mt-4">
              <label for="user_status">{label(@locale, "status")}</label>
              <select class="select select-bordered w-full" name="user[status]" id="user_status">
                <option
                  :for={{status, index} <- @statuses}
                  value={status}
                  selected={@target.status == index && "selected"}
                >
                  {t(@locale, "enums.user.status." <> status, %{})}
                </option>
              </select>
            </div>
            <div class="form-control mt-5">
              <input
                type="submit"
                name="commit"
                value={label(@locale, "update")}
                class="btn btn-primary"
                data-disable-with={label(@locale, "update")}
              />
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp label(locale, key), do: t(locale, "settings.users.edit." <> key, %{})
end
