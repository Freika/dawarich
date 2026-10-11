defmodule DawarichWeb.AuthTwoFactor.Form do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.SettingsParts, only: [navigation: 1]

  embed_templates "form/*"

  def page(assigns) do
    assigns = assign(assigns, :active, if(assigns.kind == :show, do: "two_factor", else: nil))

    assigns =
      if assigns.kind == :verify,
        do: assign(assigns, :qr_svg, Dawarich.QrSvg.otp(assigns.uri)),
        else: assigns

    case assigns.kind do
      :show -> show(assigns)
      :verify -> verify(assigns)
      :backup_codes -> backup_codes(assigns)
    end
  end

  def title(kind, locale) do
    key =
      case kind do
        :show -> "show.two_factor_authentication"
        :verify -> "verify.set_up_two_factor_authentication"
        :backup_codes -> "backup_codes.backup_codes"
      end

    t(locale, "settings.two_factor." <> key, %{})
  end
end
