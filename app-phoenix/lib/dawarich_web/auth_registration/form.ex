defmodule DawarichWeb.AuthRegistration.Form do
  @moduledoc false
  use Phoenix.Component
  embed_templates "form/*"

  def render(token, email, messages, invitation, locale) do
    new(%{
      __changed__: nil,
      token: token,
      email: email,
      messages: messages,
      invitation: invitation,
      locale: locale
    })
    |> Phoenix.HTML.Safe.to_iodata()
  end

  defp text(locale, key),
    do: DawarichWeb.Translate.t(locale, "devise.registrations.new." <> key, %{})
end
