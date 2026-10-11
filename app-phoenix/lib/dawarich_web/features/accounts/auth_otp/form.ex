defmodule DawarichWeb.AuthOtp.Form do
  @moduledoc false
  use DawarichWeb, :html
  embed_templates "form/*"

  def page(assigns), do: challenge(assigns)
  def title(locale), do: text(locale, "two_factor_authentication")
  def text(locale, key), do: t(locale, "devise.sessions.otp_challenge." <> key, %{})
end
