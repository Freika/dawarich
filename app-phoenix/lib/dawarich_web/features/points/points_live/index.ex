defmodule DawarichWeb.PointsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Phoenix.LiveView.JS
  alias Dawarich.Points.Pages
  alias DawarichWeb.PointsLive.Actions

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
       selected: MapSet.new(),
       point_dialog: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = socket |> DataAsync.advance() |> Actions.reset()

    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, result} <-
           Pages.load(scope, Map.delete(params, "locale"),
             now: DateTime.utc_now(),
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

  def handle_event(event, params, socket),
    do: {:noreply, Actions.event(event, params, socket)}

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
    <div class="w-full my-5">
      <DawarichWeb.ListParts.page_header title={t(@locale, "points.index.points", %{})} />
      <div
        :if={@point_dialog}
        id="points_dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="points_dialog_title"
        class="fixed inset-0 z-50 bg-base-100/95 p-6 flex flex-col items-center justify-center gap-4 min-w-0"
        phx-window-keydown="cancel_action"
        phx-key="escape"
        phx-mounted={JS.focus(to: "#points_cancel")}
      >
        <h2 id="points_dialog_title" class="text-xl break-words">
          {t(
            @locale,
            if(@point_dialog == :delete,
              do: "points.index.delete_selected",
              else: "points.index.export"
            ),
            %{}
          )}
        </h2>
        <div class="flex flex-wrap gap-3">
          <button id="points_cancel" phx-click="cancel_action" class="btn whitespace-normal h-auto">{t(
            @locale,
            "cancel",
            %{}
          )}</button>
          <button
            id="points_confirm"
            phx-click="confirm_action"
            phx-disable-with="…"
            class="btn btn-primary whitespace-normal h-auto"
          >{t(
            @locale,
            if(@point_dialog == :delete,
              do: "points.index.delete_selected",
              else: "points.index.export"
            ),
            %{}
          )}</button>
        </div>
      </div>
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
          class="flex justify-center mb-4"
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
          class="flex justify-center mt-4"
        />
      <% end %>
    </div>
    """
  end
end
