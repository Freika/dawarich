defmodule DawarichWeb.NativePublicDocument do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.AchievementPublicHTML
  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :base_url, :string, required: true
  attr :uuid, :string, required: true
  attr :embed, :boolean, default: false

  def document(%{page: %{kind: :month}} = assigns),
    do: DawarichWeb.NativePublicMonth.document(assigns)

  def document(%{page: %{card: _} = page} = assigns) do
    AchievementPublicHTML.html(%{
      __changed__: nil,
      view: page,
      locale: page.locale,
      base_url: assigns.base_url,
      rails_csrf_token: "",
      embed: assigns.embed,
      native: true
    })
    |> Phoenix.HTML.raw()
  end

  def document(assigns), do: DawarichWeb.PublicReportDocument.document(assigns)
end
