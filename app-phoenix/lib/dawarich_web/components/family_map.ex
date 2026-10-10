defmodule DawarichWeb.FamilyMap do
  @moduledoc false
  use Phoenix.Component
  attr :id, :string, default: "native-family-map"
  attr :locale, :string, default: "en"
  attr :config, :map, default: %{}

  def family_map(assigns) do
    locale =
      if assigns.locale in Dawarich.I18n.available_locales(), do: assigns.locale, else: "en"

    scope =
      if locale == "de",
        do: "datetime.distance_in_words.dative",
        else: "datetime.distance_in_words"

    {:ok, words} = Dawarich.I18n.t(locale, scope)
    {:ok, ago} = Dawarich.I18n.t(locale, "common.time_ago", %{"time" => "%{time}"})
    {:ok, middot} = Dawarich.I18n.t(locale, "families.show.middot")

    config =
      assigns.config
      |> Map.take(~w(revision styleUrl range mapOptions))
      |> Map.update("range", %{}, &Map.take(&1, ~w(startAt endAt timezone)))
      |> Map.update(
        "mapOptions",
        %{},
        &Map.take(&1, ~w(center zoom interactive attributionControl))
      )
      |> Map.put("locale", locale)
      |> Map.put("familyTime", %{words: words, ago: ago, middot: middot})

    assigns = assign(assigns, :serialized_config, Jason.encode!(config))

    ~H"""
    <div
      id={@id}
      class="relative min-w-0 w-full h-full min-h-80 overflow-hidden rounded-xl"
      phx-hook="Family"
      phx-update="ignore"
      data-map-config={@serialized_config}
      data-map-state="loading"
    >
      <p
        data-family-empty
        class="absolute inset-0 flex items-center justify-center p-6 text-center bg-base-200 [overflow-wrap:anywhere]"
      >
        {DawarichWeb.Translate.t(
          @locale,
          "families.show.no_family_members_are_sharing_their_location",
          %{}
        )}
      </p>
    </div>
    """
  end
end
