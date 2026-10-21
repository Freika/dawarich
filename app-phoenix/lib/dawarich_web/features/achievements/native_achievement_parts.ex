defmodule DawarichWeb.NativeAchievementParts do
  @moduledoc false
  use DawarichWeb, :html
  alias Phoenix.LiveView.JS
  alias DawarichWeb.AchievementCard
  attr :panel, :any, default: nil
  attr :data, :any, required: true
  attr :selected, :any, required: true
  attr :share_url, :any, required: true
  attr :base_url, :string, required: true
  attr :locale, :string, required: true

  def page(assigns) do
    ~H"""
    <div id="native-achievements" class="w-full my-5 ach-page">
      <%= if @data do %>
        <DawarichWeb.NativeAchievementDetail.detail
          :if={@data.view[:set]}
          data={@data}
          locale={@locale}
        />
        <DawarichWeb.NativeAchievementIndex.index
          :if={!@data.view[:set]}
          data={@data}
          locale={@locale}
        />
      <% end %>
      <DawarichWeb.NativeAchievementDialog.dialog
        selected={@selected}
        share_url={@share_url}
        panel={@panel}
        locale={@locale}
        base_url={@base_url}
      />
    </div>
    """
  end

  def interactive_card(assigns) do
    assigns = assign_new(assigns, :small, fn -> false end)

    ~H"""
    <AchievementCard.card
      card={@item.card}
      locale={@locale}
      celebrate={@item.celebrate}
      modal
      small={@small}
      share={
        if @item.share_key,
          do: %{"key" => @item.share_key, "shared" => @item.shared, "uuid" => @item.uuid}
      }
      native
      native_key={@item.key}
    />
    """
  end

  def item(set), do: hd(cards(%{view: %{sets: [set], orphans: [], continents: []}}))

  def open(key),
    do:
      JS.push_focus()
      |> JS.push("select_card", value: %{key: key})
      |> JS.dispatch("dawarich:open-dialog", to: "#native-achievement-dialog")

  def close,
    do:
      JS.push("close_card")
      |> JS.dispatch("dawarich:close-dialog", to: "#native-achievement-dialog")
      |> JS.pop_focus()

  def path(query, extra) do
    key = query["key"]
    base = if key, do: "/achievements/" <> key, else: "/achievements"
    values = query |> Map.drop(~w(key page)) |> Map.merge(extra)
    base <> "?" <> URI.encode_query(values)
  end

  def cards(data) do
    view = data.view
    sets = if view[:set], do: [view.set], else: view.sets ++ view.orphans

    Enum.map(sets, fn set ->
      %{
        key: set["key"],
        card: set["card"],
        route:
          if(set["parent_key"] || set["key"] in Enum.map(view.continents, & &1["key"]),
            do: "/achievements/" <> set["key"]
          ),
        share_key: set["key"],
        shared: set["sharing_enabled"],
        uuid: set["sharing_uuid"],
        celebrate: set["celebrate"]
      }
    end) ++
      Enum.map(view[:children] || [], fn card ->
        %{
          key: card["share_key"] || card["code"],
          card: card,
          route: card["key"] && "/achievements/" <> card["key"],
          share_key: card["share_key"],
          shared: card["share"] && card["share"]["shared"],
          uuid: card["share"] && card["share"]["uuid"],
          celebrate: false
        }
      end)
  end
end
