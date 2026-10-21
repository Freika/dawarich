defmodule DawarichWeb.AuthRecovery.Form do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.Auth.Recovery.{Messages, Token}
  embed_templates "form/*"

  def render(view, csrf, values, locale, registration_enabled, opts \\ []) do
    {scope, title, description, submit, path} = config(view)
    error = values[:error]

    links =
      [{"/users/sign_in", "log_in"}] ++
        if(registration_enabled, do: [{"/users/sign_up", "register"}], else: []) ++
        if(view == :unlock_new,
          do: [{"/users/password/new", "forgot_your_password"}],
          else: [{"/users/unlock/new", "didn_t_receive_unlock_instructions"}]
        )

    assigns = %{
      __changed__: nil,
      providers: Keyword.get(opts, :providers, []),
      view: view,
      csrf: csrf,
      token: if(Token.blank?(values[:token]), do: nil, else: values[:token]),
      locale: locale,
      scope: scope,
      title: title,
      description: description,
      submit: submit,
      path: path,
      links: links,
      invalid: Messages.attributes(error),
      errors: if(error, do: Messages.error(view, error, locale)),
      form_id:
        if(view == :password_edit and error not in [nil, :invalid, :blank_token],
          do: "edit_user",
          else: "new_user"
        )
    }

    request(assigns) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  end

  defp text(assigns, key), do: t(assigns.locale, assigns.scope <> key, %{})

  defp described(invalid, field, hint \\ nil) do
    case Enum.reject([hint, if(field in invalid, do: "error_explanation")], &is_nil/1) do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  defp config(:password_new),
    do:
      {"devise.passwords.new.", "forgot_your_password",
       "enter_your_email_address_and_we_ll_send_you_instructions",
       "send_me_reset_password_instructions", "/users/password"}

  defp config(:password_edit),
    do:
      {"devise.passwords.edit.", "change_your_password", "enter_your_new_password_below",
       "change_my_password", "/users/password"}

  defp config(:unlock_new),
    do:
      {"devise.unlocks.new.", "resend_unlock_instructions",
       "enter_your_email_address_and_we_ll_send_you_instructions", "resend_unlock_instructions",
       "/users/unlock"}
end
