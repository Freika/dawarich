defmodule DawarichWeb.AuthRegistration.Form do
  @moduledoc false
  use Phoenix.Component
  embed_templates "form/*"

  def render(token, email, messages, invitation, locale, opts \\ []) do
    new(%{
      __changed__: nil,
      token: token,
      email: email,
      messages: messages,
      invalid: Keyword.get(opts, :invalid, []),
      invitation: invitation,
      locale: locale,
      self_hosted: Keyword.get(opts, :self_hosted, true),
      sitekey: Keyword.get(opts, :sitekey, ""),
      providers: Keyword.get(opts, :providers, [])
    })
    |> Phoenix.HTML.Safe.to_iodata()
  end

  defp text(locale, key, bindings \\ %{}),
    do: DawarichWeb.Translate.t(locale, "devise.registrations.new." <> key, bindings)
end
