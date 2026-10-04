defmodule DawarichWeb.TagsLive.Form do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.TagPages
  alias DawarichWeb.TagForm

  @emojis ~w(
    🏠 🏢 🏫 🏥 🏪 🏨 🏦 🏛️ 🏟️ 🏖️
    ⛪ 🕌 🕍 ⛩️ 🗼 🗽 🗿 💒 🏰 🏯
    🍕 🍔 🍟 🍣 🍱 🍜 🍝 🍛 🥘 🍲
    ☕ 🍺 🍷 🥂 🍹 🍸 🥃 🍻 🥤 🧃
    🏃 ⚽ 🏀 🏈 ⚾ 🎾 🏐 🏓 🏸 🏒
    🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐
    ✈️ 🚁 ⛵ 🚤 🛥️ ⛴️ 🚂 🚆 🚇 🚊
    🎭 🎪 🎨 🎬 🎤 🎧 🎼 🎹 🎸 🎺
    📚 📖 ✏️ 🖊️ 📝 📋 📌 📍 🗺️ 🧭
    💼 👔 🎓 🏆 🎯 🎲 🎮 🎰 🛍️ 💍
  )

  def default_emoji, do: Enum.random(@emojis)

  def live_session(conn) do
    session = DawarichWeb.RailsAuth.live_session(conn)

    if conn.request_path == "/tags/new",
      do: Map.put(session, "tag_default_emoji", default_emoji()),
      else: session
  end

  @impl true
  def mount(_params, session, socket),
    do: {:ok, assign(socket, default_emoji: session["tag_default_emoji"])}

  @impl true
  def handle_params(params, uri, socket) do
    result =
      if socket.assigns.live_action == :new,
        do: {:ok, %{id: nil, name: nil, icon: nil, color: nil, privacy_radius_meters: nil}},
        else: TagPages.edit(socket.assigns.current_user, String.to_integer(params["id"]))

    case result do
      {:ok, tag} ->
        kind = if tag.id, do: "edit", else: "new"
        title = t(socket.assigns.locale, "tags.#{kind}.#{kind}_tag", %{})
        {:noreply, assign(socket, tag: tag, kind: kind, tag_title: title, page_title: nil)}

      :rails ->
        %URI{path: path, query: query} = URI.parse(uri)
        {:noreply, redirect(socket, to: if(query, do: path <> "?" <> query, else: path))}
    end
  end

  @impl true
  def render(assigns), do: page(assigns)

  def page(assigns) do
    assigns = Map.put_new(assigns, :tag_errors, [])

    ~H"""
    <div class="container mx-auto px-4 py-8 max-w-2xl">
      <div class="mb-6">
        <h1 class="text-3xl font-bold">{@tag_title}</h1>
        <p class="text-gray-600 mt-2">
          {t(
            @locale,
            "tags.#{@kind}." <>
              if(@kind == "new",
                do: "create_a_new_tag_to_organize_your_places",
                else: "update_your_tag_details"
              ),
            %{}
          )}
        </p>
      </div>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <TagForm.form
            locale={@locale}
            tag={@tag}
            csrf={@rails_csrf_token}
            emoji={@default_emoji}
            errors={@tag_errors}
          />
        </div>
      </div>
    </div>
    """
  end
end
