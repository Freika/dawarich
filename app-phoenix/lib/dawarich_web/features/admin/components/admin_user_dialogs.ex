defmodule DawarichWeb.AdminUserDialogs do
  @moduledoc false
  use DawarichWeb, :html
  alias Phoenix.LiveView.JS

  attr :csrf, :string, default: "CSRF"
  attr :locale, :string, required: true
  attr :rows, :list, required: true
  attr :create_email, :string, required: true
  attr :form_version, :integer, required: true
  attr :delete_id, :integer, default: nil
  attr :open, :boolean, default: false
  attr :error, :string, default: nil

  def dialogs(assigns) do
    assigns =
      assign(
        assigns,
        :delete_email,
        case Enum.find(assigns.rows, &(&1.id == assigns.delete_id)) do
          nil -> ""
          user -> user.email
        end
      )

    ~H"""
    <dialog
      id="create_user"
      class="modal"
      open={@open}
      phx-mounted={JS.ignore_attributes("open")}
      phx-window-keydown={JS.push("close_create") |> JS.dispatch("dawarich:close-dialog")}
      phx-key="Escape"
    >
      <div class="modal-box">
        <h2 class="text-2xl font-bold">{label(@locale, "create_a_new_user")}</h2>
        <p :if={@error} role="alert" class="text-error">{@error}</p>
        <form
          id={"native-create-user-form-#{@form_version}"}
          action="/settings/users"
          accept-charset="UTF-8"
          method="post"
          phx-submit="create_user"
        >
          <input type="hidden" name="authenticity_token" value={@csrf} />
          <div class="form-control">
            <label for="user_email">{label(@locale, "email")}</label>
            <input
              id="user_email"
              type="email"
              name="user[email]"
              value={@create_email}
              class="input input-bordered"
            />
          </div>
          <div class="form-control mt-5">
            <label for="user_password">{label(@locale, "password")}</label>
            <input
              id="user_password"
              phx-patch-focused
              type="password"
              name="user[password]"
              autocomplete="new-password"
              autofocus="autofocus"
              minlength="12"
              maxlength="128"
              size="128"
              required="required"
              aria-describedby="create-user-password-hint"
              class="input input-bordered"
            />
            <p id="create-user-password-hint" class="text-sm text-base-content/70 mt-1">
              {t(@locale, "devise.registrations.new.characters_minimum", %{count: 12})}
            </p>
          </div>
          <div class="form-control mt-5">
            <input
              type="submit"
              name="commit"
              value={label(@locale, "create")}
              class="btn btn-primary"
              phx-disable-with={label(@locale, "create")}
            />
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click={
          JS.push("close_create") |> JS.dispatch("dawarich:close-dialog", to: "#create_user")
        }>
          {label(@locale, "close")}
        </button>
      </form>
    </dialog>
    <dialog id="delete_user" class="modal" open={@open} phx-mounted={JS.ignore_attributes("open")}>
      <div class="modal-box">
        <h3 class="text-lg font-bold">{label(@locale, "delete_user")}</h3>
        <p class="py-4">
          {label(@locale, "are_you_sure_you_want_to_delete")} <strong>{@delete_email}</strong>{label(
            @locale,
            "this_will_permanently_remove_their_account_and_all_associated_data"
          )}
        </p>
        <div class="modal-action">
          <form method="dialog">
            <button
              id="native-cancel-delete"
              class="btn"
              phx-click={
                JS.push("cancel_delete") |> JS.dispatch("dawarich:close-dialog", to: "#delete_user")
              }
            >{label(@locale, "cancel")}</button>
          </form>
          <form
            id="native-delete-user-form"
            class="button_to"
            method="post"
            action={"/settings/users/#{@delete_id}"}
            phx-submit="delete_user"
          >
            <input type="hidden" name="_method" value="delete" />
            <button
              id="native-confirm-delete"
              type="submit"
              class="btn btn-error"
              disabled={is_nil(@delete_id)}
              phx-disable-with={label(@locale, "delete")}
            >{label(@locale, "delete")}</button>
            <input type="hidden" name="authenticity_token" value={@csrf} />
          </form>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click={
          JS.push("cancel_delete") |> JS.dispatch("dawarich:close-dialog", to: "#delete_user")
        }>
          {label(@locale, "close")}
        </button>
      </form>
    </dialog>
    """
  end

  defp label(locale, key), do: t(locale, "settings.users.index." <> key, %{})
end
