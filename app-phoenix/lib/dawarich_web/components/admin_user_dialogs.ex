defmodule DawarichWeb.AdminUserDialogs do
  @moduledoc false
  use DawarichWeb, :html

  attr :locale, :string, required: true
  attr :rows, :list, required: true
  attr :actor, :map, required: true
  attr :rails_csrf_token, :string, required: true

  def dialogs(assigns) do
    ~H"""
    <dialog id="create_user" class="modal" phx-update="ignore">
      <div class="modal-box">
        <h2 class="text-2xl font-bold">
          {t(@locale, "settings.users.index.create_a_new_user", %{})}
        </h2>
        <form
          data-turbo-method="post"
          data-turbo="false"
          action="/settings/users"
          accept-charset="UTF-8"
          method="post"
        >
          <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
          <div class="form-control">
            <label for="user_email">{t(@locale, "settings.users.index.email", %{})}</label>
            <input
              value=""
              class="input input-bordered"
              type="email"
              name="user[email]"
              id="user_email"
            />
          </div>
          <div class="form-control mt-5">
            <label for="user_password">{t(@locale, "settings.users.index.password", %{})}</label>
            <input
              autofocus="autofocus"
              autocomplete="new-password"
              class="input input-bordered"
              minlength="12"
              maxlength="128"
              required="required"
              aria-describedby="create-user-password-hint"
              size="128"
              type="password"
              name="user[password]"
              id="user_password"
            />
            <p id="create-user-password-hint" class="text-sm text-base-content/70 mt-1">
              {t(@locale, "devise.registrations.new.characters_minimum", %{count: 12})}
            </p>
          </div>
          <div class="form-control mt-5">
            <input
              type="submit"
              name="commit"
              value={t(@locale, "settings.users.index.create", %{})}
              class="btn btn-primary"
              data-disable-with={t(@locale, "settings.users.index.create", %{})}
            />
          </div>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>{t(@locale, "settings.users.index.close", %{})}</button>
      </form>
    </dialog>
    <dialog
      :for={user <- @rows}
      :if={user.id != @actor.id}
      id={"delete_user_#{user.id}"}
      class="modal"
      phx-update="ignore"
    >
      <div class="modal-box">
        <h3 class="text-lg font-bold">{t(@locale, "settings.users.index.delete_user", %{})}</h3>
        <p class="py-4">
          {t(@locale, "settings.users.index.are_you_sure_you_want_to_delete", %{})} <strong>{user.email}</strong>{t(
            @locale,
            "settings.users.index.this_will_permanently_remove_their_account_and_all_associated_data",
            %{}
          )}
        </p>
        <div class="modal-action">
          <form method="dialog">
            <button class="btn">{t(@locale, "settings.users.index.cancel", %{})}</button>
          </form>
          <form class="button_to" method="post" action={"/settings/users/#{user.id}"}>
            <input type="hidden" name="_method" value="delete" />
            <button class="btn btn-error" data-turbo="false" type="submit">{t(
              @locale,
              "settings.users.index.delete",
              %{}
            )}</button>
            <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
          </form>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>{t(@locale, "settings.users.index.close", %{})}</button>
      </form>
    </dialog>
    """
  end
end
