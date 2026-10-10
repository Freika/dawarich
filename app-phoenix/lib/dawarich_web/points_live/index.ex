defmodule DawarichWeb.PointsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Points.Pages

  alias DawarichWeb.{
    DataAsync,
    NativeDataAuth,
    PointListControls,
    PointListFormat,
    PointListTable
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: t(socket.assigns.locale, "points.index.points", %{}),
       rows: [],
       imports: [],
       window: nil,
       query: %{},
       summary: "",
       page: 1,
       total_pages: 0,
       geocoding: false,
       unit: "km",
       selected: MapSet.new()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = socket |> DataAsync.advance() |> assign(:selected, MapSet.new())

    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, result} <-
           Pages.load(scope, params,
             now: socket.assigns.now,
             self_hosted: socket.assigns.self_hosted
           ) do
      summary =
        PointListFormat.entries(
          socket.assigns.locale,
          result.count,
          result.page,
          length(result.rows),
          result.total_pages
        )

      {:noreply,
       socket |> assign(result) |> assign(summary: summary, filter_form: to_form(result.query))}
    else
      {:error, reason} ->
        {:noreply, socket |> assign(:rows, []) |> NativeDataAuth.refuse(reason, "/points")}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    query = Map.merge(socket.assigns.query, params) |> Map.put("page", "1")

    case Pages.normalize(query) do
      {:ok, normalized, search} ->
        {:noreply,
         push_patch(socket,
           to: PointListFormat.url("/points", Map.put(normalized.params, "import_search", search))
         )}

      _ ->
        {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  end

  def handle_event(_event, _params, socket),
    do: {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}

  @impl true
  def handle_async(name, result, socket) do
    case DataAsync.finish(socket, name, result) do
      {:stale, socket} -> {:noreply, socket}
      {:ok, _projection, socket} -> {:noreply, socket}
      {:error, reason, socket} -> {:noreply, NativeDataAuth.refuse(socket, reason)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full min-w-0 my-5">
      <h1 class="text-3xl font-bold mb-6 break-words">{t(@locale, "points.index.points", %{})}</h1>
      <%= if @window do %>
        <PointListControls.controls
          locale={@locale}
          window={@window}
          imports={@imports}
          query={@query}
          summary={@summary}
          form={@filter_form}
        />
        <PointListControls.pagination
          locale={@locale}
          query={@query}
          page={@page}
          total_pages={@total_pages}
          class="flex flex-wrap justify-center mb-4"
        />
        <PointListTable.table
          locale={@locale}
          rows={@rows}
          query={@query}
          geocoding={@geocoding}
          unit={@unit}
          selected={@selected}
        />
        <PointListControls.pagination
          locale={@locale}
          query={@query}
          page={@page}
          total_pages={@total_pages}
          class="flex flex-wrap justify-center mt-4"
        />
      <% end %>
    </div>
    """
  end
end
