defmodule DawarichWeb.NativePublicResource do
  @moduledoc false
  use DawarichWeb, :html

  attr :presentation, :map, required: true
  attr :selected_day, :string, default: nil
  attr :locale, :string, required: true
  attr :gallery_days, :any, default: MapSet.new()
  attr :config, :map, required: true

  def resource(%{presentation: %{resource: nil}} = assigns), do: ~H""

  def resource(assigns) do
    ~H"""
    <DawarichWeb.SharedResourcePage.resource
      locale={@locale}
      link={@presentation.link}
      resource={@presentation.resource}
      map_config={@config}
      selected_day={@selected_day}
      gallery_days={@gallery_days}
      native
    />
    <button
      :if={@presentation.resource[:next_cursor]}
      type="button"
      phx-click="public:more"
      class="btn btn-sm max-w-full whitespace-normal"
    >
      {Phoenix.HTML.raw(t(@locale, "views.pagination.next", %{}))}
    </button>
    """
  end
end
