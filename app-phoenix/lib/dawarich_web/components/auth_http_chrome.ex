defmodule DawarichWeb.AuthHttpChrome do
  @moduledoc false
  use DawarichWeb, :html

  attr :locale, :string, required: true
  attr :flash, :map, default: %{}
  attr :flash_messages, :list, default: []

  def flash(assigns) do
    messages =
      Enum.reduce(assigns.flash, assigns.flash_messages, fn {type, message}, list ->
        List.keystore(list, type, 0, {type, message})
      end)

    assigns = assign(assigns, :messages, messages)

    ~H"""
    <div
      id="flash-messages"
      class="fixed top-5 right-5 max-w-[calc(100vw-2.5rem)] flex flex-col gap-2 z-50 pointer-events-none"
    >
      <DawarichWeb.Chrome.flash_message
        :for={{type, message} <- @messages}
        type={type}
        message={message}
        locale={@locale}
        native
        http
      />
    </div>
    """
  end

  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def sign_out(assigns) do
    ~H"""
    <form method="post" action="/users/sign_out" data-auth-form class="contents">
      <input type="hidden" name="_method" value="delete" />
      <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
      <button type="submit" class="w-full text-left focus-visible:outline focus-visible:outline-2">{t(
        @locale,
        "shared.navbar.logout",
        %{}
      )}</button>
    </form>
    """
  end

  attr :locale, :string, required: true
  attr :active, :string, required: true
  attr :self_hosted, :boolean, required: true
  attr :admin, :boolean, required: true
  attr :two_factor, :boolean, required: true

  def settings_navigation(assigns) do
    ~H"""
    <DawarichWeb.SettingsParts.navigation
      locale={@locale}
      active={@active}
      self_hosted={@self_hosted}
      admin={@admin}
      two_factor={@two_factor}
      native
      http
    />
    """
  end
end
