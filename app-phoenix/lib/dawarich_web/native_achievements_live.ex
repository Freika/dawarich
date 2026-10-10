defmodule DawarichWeb.NativeAchievementsLive do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Achievements.{Commands, Pages}
  alias DawarichWeb.{NativeDataAuth, NativeAchievementParts}

  @impl true
  def mount(_, _, socket),
    do:
      {:ok,
       assign(socket,
         data: nil,
         selected: nil,
         share_url: nil,
         page_title: t(socket.assigns.locale, "achievements.ui.title", %{})
       )}

  @impl true
  def handle_params(params, _, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, data} <- Pages.load(scope, params) do
      data = acknowledge(scope, data, connected?(socket))
      selected = find(data, socket.assigns.selected && socket.assigns.selected.key)

      socket =
        assign(socket,
          data: data,
          selected: selected,
          share_url: url(selected),
          page_title:
            if(data.view[:set], do: data.view.set["name"], else: socket.assigns.page_title)
        )

      socket =
        if is_nil(selected),
          do: push_event(socket, "close-dialog", %{id: "achievement-dialog"}),
          else: socket

      {:noreply, socket}
    else
      {:redirect, path} ->
        {:noreply, redirect(socket, to: path)}

      {:error, :not_found} ->
        {:noreply, redirect(socket, to: "/achievements")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(data: nil, selected: nil, share_url: nil)
         |> NativeDataAuth.refuse(reason)}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    with {:ok, query} <- Pages.normalize(params),
         data when not is_nil(data) <- socket.assigns.data do
      query = query |> Map.take(Map.keys(params)) |> Map.take(~w(q status))
      {:noreply, push_patch(socket, to: NativeAchievementParts.path(data.query, query))}
    else
      _ -> {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  end

  def handle_event("select_card", %{"key" => key}, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, fresh} <- Pages.load(scope, socket.assigns.data.query),
         selected when not is_nil(selected) <- find(fresh, key) do
      {:noreply, assign(socket, selected: selected, share_url: url(selected))}
    else
      _ -> {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  end

  def handle_event("close_card", _, socket),
    do: {:noreply, assign(socket, selected: nil, share_url: nil)}

  def handle_event("share_card", %{"enabled" => enabled}, socket) do
    with selected when not is_nil(selected) <- socket.assigns.selected,
         key when is_binary(key) <- selected.share_key,
         {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, result} <- Commands.share(scope, key, %{"enabled" => enabled == "true"}) do
      {:noreply, assign(socket, share_url: if(result.enabled, do: result.url, else: nil))}
    else
      _ -> {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  rescue
    _ -> {:noreply, NativeDataAuth.refuse(socket, :unavailable)}
  end

  def handle_event(_, _, socket), do: {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}

  @impl true
  def render(assigns) do
    ~H"""
    <NativeAchievementParts.page
      data={@data}
      selected={@selected}
      share_url={@share_url}
      locale={@locale}
      base_url={@base_url}
    />
    """
  end

  defp acknowledge(_scope, data, false), do: data

  defp acknowledge(scope, data, true) do
    keys =
      case Commands.acknowledge(scope, data.query) do
        {:ok, keys} -> keys
        _ -> []
      end

    mark = &Map.put(&1, "celebrate", &1["key"] in keys)

    view =
      if data.view[:set],
        do: Map.update!(data.view, :set, mark),
        else:
          data.view
          |> Map.update!(:sets, &Enum.map(&1, mark))
          |> Map.update!(:orphans, &Enum.map(&1, mark))

    %{data | view: view, celebrations: keys}
  end

  def find(_data, nil), do: nil
  def find(data, key), do: Enum.find(NativeAchievementParts.cards(data), &(&1.key == key))

  defp url(%{shared: true, uuid: uuid}) when is_binary(uuid), do: "/shared/achievements/" <> uuid
  defp url(_), do: nil
end
