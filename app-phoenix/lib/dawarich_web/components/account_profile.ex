defmodule DawarichWeb.AccountProfile do
  @moduledoc false
  use DawarichWeb, :html

  @minimum_password_length 12

  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :oauth, :string, default: nil
  attr :rails_csrf_token, :string, default: nil
  attr :errors, :list, default: []
  attr :submitted_email, :string, default: nil

  def profile(assigns) do
    resource =
      case Dawarich.I18n.t(assigns.locale, "activerecord.models.user", %{"count" => 1}) do
        {:ok, value} when is_binary(value) -> String.downcase(value)
        _ -> "user"
      end

    {:ok, heading} =
      Dawarich.I18n.t(assigns.locale, "errors.messages.not_saved", %{
        "count" => length(assigns.errors),
        "resource" => resource
      })

    assigns =
      assigns
      |> assign(:minimum, @minimum_password_length)
      |> assign(:invalid, Enum.map(assigns.errors, &elem(&1, 0)))
      |> assign(
        :messages,
        Dawarich.Auth.AccountValidation.messages(assigns.errors, assigns.locale)
      )
      |> assign(:heading, heading)

    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body gap-5 p-5 sm:p-6">
        <div>
          <h2 class="card-title text-2xl">{t(@locale, "devise.registrations.edit.profile", %{})}</h2>
          <p class="mt-1 text-sm text-base-content/70">
            {t(
              @locale,
              "devise.registrations.edit.update_your_email_address_and_password_from_one_place",
              %{}
            )}
          </p>
        </div>
        <div
          :if={@oauth}
          class="rounded-xl border border-base-300 bg-base-200/50 px-4 py-3 text-sm font-medium"
        >
          {t(@locale, "devise.registrations.edit.connected_with", %{})} {@oauth}
        </div>
        <form
          class="edit_user"
          id="edit_user"
          phx-update="ignore"
          data-turbo-method="put"
          data-turbo="false"
          action="/users"
          accept-charset="UTF-8"
          method="post"
        >
          <input type="hidden" name="_method" value="put" /><input
            :if={@rails_csrf_token}
            type="hidden"
            name="authenticity_token"
            value={@rails_csrf_token}
          />
          <div
            :if={@errors != []}
            id="error_explanation"
            class="alert alert-error mb-4"
            data-turbo-cache="false"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
              class="size-6"
            ><circle cx="12" cy="12" r="10"></circle><path d="m15 9-6 6"></path><path d="m9 9 6 6">
            </path></svg>
            <div class="font-bold mb-4 flex items-center gap-2">
              <div>
                <h3 class="font-bold">{@heading}</h3><ul class="text-sm mt-1">
                  <li :for={message <- @messages}>{message}</li>
                </ul>
              </div>
            </div>
          </div>
          <div :for={field <- [:first_name, :last_name]} class="form-control">
            <label class="label" for={"user_#{field}"}><span class="label-text">{t(
              @locale,
              "devise.registrations.edit.#{field}",
              %{}
            )}</span></label>
            <input
              class="input input-bordered w-full"
              type="text"
              value={Map.get(@user, field)}
              name={"user[#{field}]"}
              id={"user_#{field}"}
              autocomplete={if field == :first_name, do: "given-name", else: "family-name"}
            />
          </div>
          <div class="form-control">
            <.field_error invalid={:email in @invalid}>
              <label class="label" for="user_email"><span class="label-text">{t(
                @locale,
                "devise.registrations.edit.email",
                %{}
              )}</span></label>
            </.field_error>
            <.field_error invalid={:email in @invalid}>
              <input
                autofocus="autofocus"
                autocomplete="email"
                class="input input-bordered w-full"
                type="email"
                value={if is_nil(@submitted_email), do: @user.email, else: @submitted_email}
                name="user[email]"
                id="user_email"
              />
            </.field_error>
          </div>
          <div class="form-control mt-5">
            <.field_error invalid={:password in @invalid}>
              <label class="label" for="user_password"><span class="label-text">{t(
                @locale,
                "devise.registrations.edit.new_password",
                %{}
              )}
              <span class="text-base-content/60">{t(
                @locale,
                "devise.registrations.edit.leave_blank_to_keep_the_current_one",
                %{}
              )}</span></span></label>
            </.field_error>
            <em class="text-xs text-base-content/60">({@minimum} {t(
              @locale,
              "devise.registrations.edit.characters_minimum",
              %{}
            )}</em>
            <.field_error invalid={:password in @invalid}>
              <input
                autocomplete="new-password"
                class="input input-bordered w-full"
                type="password"
                name="user[password]"
                id="user_password"
              />
            </.field_error>
          </div>
          <div class="form-control mt-5">
            <.field_error invalid={:password_confirmation in @invalid}>
              <label class="label" for="user_password_confirmation"><span class="label-text">{t(
                @locale,
                "devise.registrations.edit.password_confirmation",
                %{}
              )}</span></label>
            </.field_error>
            <em class="text-xs text-base-content/60">({@minimum} {t(
              @locale,
              "devise.registrations.edit.characters_minimum",
              %{}
            )}</em>
            <.field_error invalid={:password_confirmation in @invalid}>
              <input
                autocomplete="new-password"
                class="input input-bordered w-full"
                type="password"
                name="user[password_confirmation]"
                id="user_password_confirmation"
              />
            </.field_error>
          </div>
          <div :if={!@oauth} class="form-control mt-5">
            <.field_error invalid={:current_password in @invalid}>
              <label class="label" for="user_current_password"><span class="label-text">{t(
                @locale,
                "devise.registrations.edit.current_password",
                %{}
              )}</span></label>
            </.field_error>
            <i class="text-xs text-base-content/60">{t(
              @locale,
              "devise.registrations.edit.required_to_confirm_your_changes",
              %{}
            )}</i>
            <.field_error invalid={:current_password in @invalid}>
              <input
                autocomplete="current-password"
                class="input input-bordered mt-2 w-full"
                type="password"
                name="user[current_password]"
                id="user_current_password"
              />
            </.field_error>
          </div>
          <div class="form-control mt-6">
            <input
              type="submit"
              name="commit"
              value={t(@locale, "devise.registrations.edit.save_changes", %{})}
              class="btn btn-primary w-full sm:w-auto"
              data-disable-with={t(@locale, "devise.registrations.edit.save_changes", %{})}
            />
          </div>
        </form>
        <div class="mt-5 space-y-2 text-sm">
          <div>
            <a class="link link-hover text-base-content/70" href="/users/unlock/new">{t(
              @locale,
              "devise.shared.links.didn_t_receive_unlock_instructions",
              %{}
            )}</a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :invalid, :boolean, required: true
  slot :inner_block, required: true

  defp field_error(assigns) do
    ~H"""
    <div :if={@invalid} class="field_with_errors">{render_slot(@inner_block)}</div>
    <%= if !@invalid do %>
      {render_slot(@inner_block)}
    <% end %>
    """
  end
end
