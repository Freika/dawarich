defmodule DawarichWeb.AuthAccountLink.Form do
  @moduledoc false
  use DawarichWeb, :html
  embed_templates "form/*"

  def page(assigns), do: challenge(assigns)
  def title(locale), do: text(locale, "confirm_account_linking")

  def text(locale, key, bindings \\ %{}),
    do: t(locale, "auth.account_links.challenge." <> key, bindings)

  def instructions(locale, email, provider) do
    email = Phoenix.HTML.html_escape(email) |> Phoenix.HTML.safe_to_string()

    text(locale, "existing_account_link_instructions_html", %{
      "email" => {:safe, "<strong>" <> email <> "</strong>"},
      "provider" => provider
    })
  end
end
