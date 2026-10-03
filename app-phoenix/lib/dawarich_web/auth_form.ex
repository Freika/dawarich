defmodule DawarichWeb.AuthForm do
  @moduledoc false

  def render(token, email \\ "", opts \\ []) do
    locale = Keyword.get(opts, :locale, "en")

    text = fn key ->
      DawarichWeb.Translate.t(locale, "devise.sessions.new." <> key, %{}) |> escape()
    end

    link = fn key ->
      DawarichWeb.Translate.t(locale, "devise.shared.links." <> key, %{}) |> escape()
    end

    registration =
      if Keyword.get(opts, :registration_enabled, false),
        do:
          "<div><a class=\"link link-hover text-base-content/70\" href=\"/users/sign_up\">#{link.("register")}</a></div>",
        else: ""

    """
    <div class="hero min-h-content bg-base-200"><div class="hero-content flex-col lg:flex-row-reverse w-full my-10">
    <div class="text-center lg:text-left"><h1 class="text-5xl font-bold text-base-content">#{text.("login_now")}</h1>
    <p class="py-6 text-base-content opacity-70">#{text.("and_take_control_over_your_location_data")}</p></div>
    <div class="card flex-shrink-0 w-full max-w-sm shadow-2xl bg-base-100 px-5 py-5">
    <form class="new_user" id="new_user" data-turbo="true" action="/users/sign_in" accept-charset="UTF-8" method="post"><input type="hidden" name="authenticity_token" value="#{escape(token)}" />
    <div class="form-control"><label class="label" for="user_email"><span class="label-text">#{text.("email")}</span></label><input autofocus="autofocus" autocomplete="email" class="input input-bordered" type="email" value="#{escape(email)}" name="user[email]" id="user_email" /></div>
    <div class="form-control"><label class="label" for="user_password"><span class="label-text">#{text.("password")}</span></label><input autocomplete="current-password" class="input input-bordered" type="password" name="user[password]" id="user_password" />
    <div class="form-control"><label class="label cursor-pointer"><span class="label-text">#{text.("remember_me")}</span><input name="user[remember_me]" type="hidden" value="0" /><input class="checkbox checkbox-sm" type="checkbox" value="1" name="user[remember_me]" id="user_remember_me" /></label></div></div>
    <div class="form-control mt-6"><input type="submit" name="commit" value="#{text.("log_in")}" class="btn btn-primary" data-disable-with="#{text.("log_in")}" /></div></form>
    <div class="mt-5 space-y-2 text-sm"><div><a class="link link-hover text-base-content/70" href="/users/sign_in">#{link.("log_in")}</a></div>#{registration}
    <div><a class="link link-hover text-base-content/70" href="/users/password/new">#{link.("forgot_your_password")}</a></div>
    <div><a class="link link-hover text-base-content/70" href="/users/unlock/new">#{link.("didn_t_receive_unlock_instructions")}</a></div></div>
    </div></div></div>
    """
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
