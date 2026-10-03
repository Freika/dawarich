defmodule DawarichWeb.AuthRecovery.Form do
  @moduledoc false
  alias Dawarich.Auth.Recovery.{Messages, Token}

  def render(view, token, assigns, locale, registration_enabled) do
    {scope, title, description, submit, path} = config(view)
    t = fn key -> DawarichWeb.Translate.t(locale, scope <> key, %{}) |> h() end
    error = assigns[:error]
    invalid = Messages.attributes(error)
    persisted = view == :password_edit and error not in [nil, :invalid, :blank_token]
    form_id = if persisted, do: "edit_user", else: "new_user"

    fields =
      if view == :password_edit do
        token_field(assigns[:token]) <>
          ~s(<div class="form-control">) <>
          label("password", t.("new_password"), invalid) <>
          ~s(<em class="text-base-content opacity-60 text-sm">\(12 #{t.("characters_minimum")}</em>) <>
          input("password", "password", "new-password", true, invalid) <>
          "</div>" <>
          ~s(<div class="form-control">) <>
          label("password_confirmation", t.("confirm_new_password"), invalid) <>
          input("password_confirmation", "password", "new-password", false, invalid) <>
          "</div>"
      else
        ~s(<div class="form-control">) <>
          label("email", t.("email"), invalid) <>
          input("email", "email", "email", true, invalid) <> "</div>"
      end

    links =
      [{"/users/sign_in", "log_in"}] ++
        if(registration_enabled, do: [{"/users/sign_up", "register"}], else: []) ++
        if(view == :unlock_new,
          do: [{"/users/password/new", "forgot_your_password"}],
          else: [{"/users/unlock/new", "didn_t_receive_unlock_instructions"}]
        )

    links =
      Enum.map_join(links, "", fn {path, key} ->
        ~s(<div><a class="link link-hover text-base-content/70" href="#{path}">#{h(DawarichWeb.Translate.t(locale, "devise.shared.links." <> key, %{}))}</a></div>)
      end)

    method = if view == :password_edit, do: hidden("_method", "put"), else: ""

    """
    <div class="hero min-h-content bg-base-200"><div class="hero-content flex-col lg:flex-row-reverse w-full my-10">
    <div class="text-center lg:text-left"><h1 class="text-5xl font-bold text-base-content">#{t.(title)}</h1><p class="py-6 text-base-content opacity-70">#{t.(description)}</p></div>
    <div class="card flex-shrink-0 w-full max-w-sm shadow-2xl bg-base-100 px-5 py-5">
    <form class="#{form_id}" id="#{form_id}" action="#{path}" accept-charset="UTF-8" method="post">#{method}#{hidden("authenticity_token", token)}#{errors(view, error, locale)}#{fields}
    <div class="form-control mt-6"><input type="submit" name="commit" value="#{t.(submit)}" class="btn btn-primary w-full" data-disable-with="#{t.(submit)}"></div></form>
    <div class="mt-5 space-y-2 text-sm">#{links}</div>
    </div></div></div>
    """
  end

  defp errors(_view, nil, _locale), do: ""

  defp errors(view, error, locale) do
    messages = Messages.error(view, error, locale)
    items = Enum.map_join(messages.messages, "", &("<li>" <> h(&1) <> "</li>"))

    ~s(<div id="error_explanation" class="alert alert-error mb-4" data-turbo-cache="false">#{icon()}<div class="font-bold mb-4 flex items-center gap-2"><div><h3 class="font-bold">#{h(messages.heading)}</h3><ul class="text-sm mt-1">#{items}</ul></div></div></div>)
  end

  defp icon do
    %{name: "circle-x", class: "size-6", aria_hidden: false, __changed__: nil}
    |> DawarichWeb.Icon.icon()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
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

  defp token_field(token) do
    value = if Token.blank?(token), do: "", else: ~s( value="#{h(token)}")

    ~s(<input type="hidden"#{value} name="user[reset_password_token]" id="user_reset_password_token">)
  end

  defp label(field, text, invalid),
    do:
      wrap(
        ~s(<label class="label" for="user_#{field}"><span class="label-text">#{text}</span></label>),
        field,
        invalid
      )

  defp input(field, type, autocomplete, autofocus, invalid) do
    focus = if autofocus, do: ~s( autofocus="autofocus"), else: ""
    value = if type == "email", do: ~s( value=""), else: ""

    wrap(
      ~s(<input#{focus} autocomplete="#{autocomplete}" class="input input-bordered w-full" type="#{type}"#{value} name="user[#{field}]" id="user_#{field}">),
      field,
      invalid
    )
  end

  defp wrap(html, field, invalid),
    do: if(field in invalid, do: ~s(<div class="field_with_errors">#{html}</div>), else: html)

  defp hidden(name, value), do: ~s(<input type="hidden" name="#{name}" value="#{h(value)}">)
  defp h(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
