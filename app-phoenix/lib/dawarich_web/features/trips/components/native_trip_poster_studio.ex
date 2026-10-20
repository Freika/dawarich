defmodule DawarichWeb.NativeTripPosterStudio do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{Icon, MapGalleryCards}
  alias Phoenix.LiveView.JS
  import DawarichWeb.EmbeddedStudios, only: [switcher: 1, poster_controls: 1, poster_order: 1]
  embed_templates "trip_studio/*"
  attr :themes, :list, required: true
  attr :posters, :list, required: true
  attr :print_order_url, :string, required: true
  attr :fixed_range_label, :string, required: true
  attr :locale, :string, required: true

  def render(assigns) do
    assigns =
      assign(assigns,
        config:
          DawarichWeb.EmbeddedStudios.poster_config(assigns.locale, assigns.print_order_url),
        target: nil
      )

    poster(assigns)
  end

  defp p(locale, key), do: t(locale, "posters.studio." <> key, %{})
end
