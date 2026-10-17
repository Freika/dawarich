defmodule DawarichWeb.AdminUserDialogs do
  @moduledoc false
  use DawarichWeb, :html
  alias Phoenix.LiveView.JS

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
    <dialog id="create_user" class="modal" open={@open} phx-mounted={JS.ignore_attributes("open")}>
      <div class="modal-box">
        <h2 class="text-2xl font-bold">{label(@locale, "create_a_new_user")}</h2>
        <p :if={@error} role="alert" class="text-error">{@error}</p>
        <form id={"create-user-form-#{@form_version}"} phx-submit="create_user">
          <label for="create-user-email">{label(@locale, "email")}</label>
          <input
            id="create-user-email"
            type="email"
            name="user[email]"
            value={@create_email}
            class="input input-bordered w-full"
            required
            autocomplete="email"
          />
          <label for="create-user-password">{label(@locale, "password")}</label>
          <input
            id="create-user-password"
            type="password"
            name="user[password]"
            value=""
            autocomplete="new-password"
            minlength="12"
            maxlength="128"
            required
            aria-describedby="create-user-password-hint"
            class="input input-bordered w-full"
          />
          <p id="create-user-password-hint" class="text-sm text-base-content/70">
            {t(@locale, "devise.registrations.new.characters_minimum", %{count: 12})}
          </p>
          <button
            type="submit"
            class="btn btn-primary mt-5"
            phx-disable-with={label(@locale, "create")}
          >{label(@locale, "create")}</button>
        </form>
        <button
          type="button"
          class="btn mt-3"
          phx-click={
            JS.push("close_create") |> JS.dispatch("dawarich:close-dialog", to: "#create_user")
          }
        >{label(@locale, "close")}</button>
      </div>
      <button
        type="button"
        class="modal-backdrop"
        aria-label={label(@locale, "close")}
        phx-click={
          JS.push("close_create") |> JS.dispatch("dawarich:close-dialog", to: "#create_user")
        }
      ></button>
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
        <div class="modal-action flex-wrap">
          <button
            id="cancel-delete"
            type="button"
            class="btn"
            phx-click={
              JS.push("cancel_delete") |> JS.dispatch("dawarich:close-dialog", to: "#delete_user")
            }
          >{label(@locale, "cancel")}</button>
          <button
            id="confirm-delete"
            type="button"
            class="btn btn-error"
            phx-click="delete_user"
            disabled={is_nil(@delete_id)}
            phx-disable-with={label(@locale, "delete")}
          >{label(@locale, "delete")}</button>
        </div>
      </div>
      <button
        type="button"
        class="modal-backdrop"
        aria-label={label(@locale, "close")}
        phx-click={
          JS.push("cancel_delete") |> JS.dispatch("dawarich:close-dialog", to: "#delete_user")
        }
      ></button>
    </dialog>
    """
  end

  defp label(locale, key), do: t(locale, "settings.users.index." <> key, %{})
end
