defmodule DawarichWeb.AuthForm do
  @moduledoc false

  def render(token, email \\ "", error \\ nil, opts \\ []) do
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

    notice = if error, do: "<div role=\"alert\">#{escape(error)}</div>", else: ""

    """
    <div class="hero min-h-content bg-base-200"><div class="hero-content flex-col lg:flex-row-reverse w-full my-10">
    <div class="text-center lg:text-left"><h1 class="text-5xl font-bold text-base-content">#{text.("login_now")}</h1>
    <p class="py-6 text-base-content opacity-70">#{text.("and_take_control_over_your_location_data")}</p></div>
    <div class="card flex-shrink-0 w-full max-w-sm shadow-2xl bg-base-100 px-5 py-5">#{notice}
    <form action="/users/sign_in" method="post">
    <input type="hidden" name="authenticity_token" value="#{escape(token)}">
    <div class="form-control"><label class="label" for="user_email">#{text.("email")}</label><input id="user_email" type="email" name="user[email]" value="#{escape(email)}" autocomplete="email" class="input input-bordered" autofocus></div>
    <div class="form-control"><label class="label" for="user_password">#{text.("password")}</label><input id="user_password" type="password" name="user[password]" autocomplete="current-password" class="input input-bordered"></div>
    <input type="hidden" name="user[remember_me]" value="0">
    <label class="label cursor-pointer" for="user_remember_me"><span class="label-text">#{text.("remember_me")}</span><input id="user_remember_me" class="checkbox checkbox-sm" type="checkbox" name="user[remember_me]" value="1"></label>
    <div class="form-control mt-6"><button class="btn btn-primary" type="submit">#{text.("log_in")}</button></div></form>
    <div class="mt-5 space-y-2 text-sm"><div><a class="link link-hover text-base-content/70" href="/users/sign_in">#{link.("log_in")}</a></div>#{registration}
    <div><a class="link link-hover text-base-content/70" href="/users/password/new">#{link.("forgot_your_password")}</a></div>
    <div><a class="link link-hover text-base-content/70" href="/users/unlock/new">#{link.("didn_t_receive_unlock_instructions")}</a></div></div>
    </div></div></div>
    """
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
