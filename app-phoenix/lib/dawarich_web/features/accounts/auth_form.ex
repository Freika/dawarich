defmodule DawarichWeb.AuthForm do
  @moduledoc false
  use DawarichWeb, :html
  embed_templates "auth_form/*"

  def render(token, email \\ "", opts \\ []) do
    new(%{
      __changed__: nil,
      token: token,
      email: email,
      locale: Keyword.get(opts, :locale, "en"),
      registration_enabled: Keyword.get(opts, :registration_enabled, false),
      email_password: Keyword.get(opts, :email_password, true),
      providers: Keyword.get(opts, :providers, []),
      invitation: Keyword.get(opts, :invitation)
    })
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
