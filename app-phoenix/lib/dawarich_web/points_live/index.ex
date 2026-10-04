defmodule DawarichWeb.PointsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  alias Dawarich.PointList
  alias DawarichWeb.{PointListControls, PointListFormat, PointListTable}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: t(socket.assigns.locale, "points.index.points", %{})),
     temporary_assigns: [rows: []]}
  end

  @impl true
  def handle_params(params, uri, socket) do
    case PointList.load(socket.assigns.current_user, params, socket.assigns.now,
           self_hosted: socket.assigns.self_hosted
         ) do
      {:ok, result} ->
        summary =
          PointListFormat.entries(
            socket.assigns.locale,
            result.count,
            result.page,
            length(result.rows),
            result.total_pages
          )

        unit = get_in(socket.assigns.current_user.settings, ["maps", "distance_unit"]) || "km"

        {:noreply,
         socket |> assign(result) |> assign(query: params, summary: summary, unit: unit)}

      :rails ->
        %URI{path: path, query: query} = URI.parse(uri)
        {:noreply, redirect(socket, to: if(query, do: path <> "?" <> query, else: path))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
        <h1 class="text-3xl font-bold">{t(@locale, "points.index.points", %{})}</h1>
      </div>
      <PointListControls.controls
        locale={@locale}
        window={@window}
        imports={@imports}
        query={@query}
        summary={@summary}
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
        csrf={@rails_csrf_token}
      />
      <PointListControls.pagination
        locale={@locale}
        query={@query}
        page={@page}
        total_pages={@total_pages}
        class="flex justify-center mt-4"
      />
    </div>
    """
  end
end
