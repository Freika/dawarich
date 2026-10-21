defmodule DawarichWeb.StatsLive.NativePage do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Stats.{Pages, Commands, PageRefresh}
  alias DawarichWeb.{DataAsync, NativeDataAuth}
  alias DawarichWeb.StatsLive.NativeParts

  @impl true
  def mount(_params, _session, socket) do
    socket = %{socket | private: Map.put(socket.private, :stats_receipt, Ecto.UUID.generate())}

    if connected?(socket) and socket.assigns.live_action == :index,
      do:
        Phoenix.PubSub.subscribe(
          Dawarich.PubSub,
          PageRefresh.topic(socket.private.data_principal.user.id)
        )

    {:ok,
     assign(socket,
       data: nil,
       query: %{},
       month_layer: "heatmap",
       stats_dialog: nil,
       page_title: t(socket.assigns.locale, "stats.index.statistics", %{})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> DataAsync.advance()
      |> assign(
        stats_dialog:
          if(
            socket.assigns.live_action == :index and params["places_kind"] in ~w(countries cities),
            do: params["places_kind"],
            else: nil
          ),
        query: Map.take(params, ~w(year month page places_page places_kind))
      )

    opts = options(socket)

    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, data} <- fetch(socket, scope, opts) do
      if socket.assigns.live_action == :index and data.points.state == :pending,
        do: PageRefresh.request(scope, :counts, socket.assigns.query, opts)

      {:noreply, socket |> assign(:data, data) |> assign(:page_title, title(socket, data))}
    else
      {:error, reason} ->
        {:noreply,
         socket |> assign(data: nil, stats_dialog: nil) |> NativeDataAuth.refuse(reason)}
    end
  end

  @impl true
  def handle_event(event, _, %{assigns: %{data: nil}} = socket)
      when event in ~w(update open_places open_share share),
      do: {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}

  def handle_event("stats:layer", %{"layer" => layer}, socket) when layer in ~w(heatmap points) do
    with {:ok, _} <- NativeDataAuth.scope(socket),
         true <- socket.assigns.live_action == :month and not is_nil(socket.assigns.data) do
      next =
        if socket.assigns.month_layer == layer,
          do: if(layer == "heatmap", do: "points", else: "none"),
          else: layer

      {:noreply, assign(socket, :month_layer, next)}
    else
      _ -> {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  end

  def handle_event("update", _params, socket) do
    params =
      if socket.assigns.live_action == :index,
        do: nil,
        else: Map.put(socket.assigns.query, "month", socket.assigns.query["month"] || "all")

    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, _} <-
           Commands.update(scope, params, socket.private.stats_receipt, command_options(socket)) do
      socket =
        put_flash(
          socket,
          :notice,
          t(socket.assigns.locale, "controllers.stats.stats_are_being_updated", %{})
        )

      socket =
        if socket.assigns.live_action == :month,
          do: push_navigate(socket, to: "/insights?year=#{socket.assigns.data.year}"),
          else: socket

      {:noreply, socket}
    else
      {:error, reason} -> {:noreply, refuse_in_place(socket, reason)}
    end
  end

  def handle_event("upgrade", _, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         false <- socket.assigns.self_hosted do
      url =
        DawarichWeb.StatsFormat.upgrade_url(
          scope.user,
          DateTime.utc_now(),
          false,
          "data_window",
          if(socket.assigns.live_action == :month, do: "stats_month", else: "stats_index")
        )

      {:noreply, redirect(socket, external: url)}
    else
      _ -> {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  end

  def handle_event("open_places", %{"kind" => kind}, %{assigns: %{live_action: :index}} = socket)
      when kind in ~w(countries cities),
      do: {:noreply, assign(socket, :stats_dialog, kind)}

  def handle_event(
        "open_year_places",
        %{"year" => year},
        %{assigns: %{live_action: :index, data: data}} = socket
      )
      when is_binary(year) and is_map(data) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, data} <- Pages.index(scope, socket.assigns.query, options(socket)),
         {year, ""} <- Integer.parse(year),
         true <- Enum.any?(data.years, &(&1.year == year)) do
      {:noreply, assign(socket, data: data, stats_dialog: {:year_places, year})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_share", _, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, result} <- Commands.sharing(scope, socket.assigns.query, command_options(socket)) do
      {:noreply, assign(socket, :stats_dialog, Map.put(result, :kind, :share))}
    else
      {:error, reason} -> {:noreply, refuse_in_place(socket, reason)}
    end
  end

  def handle_event("close_dialog", _, socket), do: {:noreply, assign(socket, :stats_dialog, nil)}

  def handle_event("share", attrs, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, result} <-
           Commands.share(scope, socket.assigns.query, attrs, command_options(socket)) do
      {:noreply, assign(socket, :stats_dialog, Map.put(result, :kind, :share))}
    else
      {:error, reason} -> {:noreply, refuse_in_place(socket, reason)}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}

  @impl true
  def handle_info({:analytics_ready, _, _}, %{assigns: %{live_action: :index}} = socket),
    do: handle_params(socket.assigns.query, "", socket)

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main :if={@live_action != :month} class="min-w-0 w-full my-5">
      <h1 class="text-3xl font-bold break-words">{@page_title}</h1>
      <NativeParts.page
        :if={@data}
        data={@data}
        locale={@locale}
        mode={@live_action}
        month_layer={@month_layer}
      />
      <button
        :if={@data && @data[:active] != false}
        id="stats-update"
        class="btn btn-primary my-4 max-w-full whitespace-normal"
        phx-click="update"
      >{t(@locale, "stats.index.update_stats", %{})}</button>
      <NativeParts.dialog
        :if={@data && @stats_dialog}
        dialog={@stats_dialog}
        data={@data}
        locale={@locale}
      />
    </main>
    <NativeParts.page
      :if={@data && @live_action == :month}
      data={@data}
      locale={@locale}
      mode={:month}
      month_layer={@month_layer}
    />
    <NativeParts.dialog
      :if={@data && @stats_dialog && @live_action == :month}
      dialog={@stats_dialog}
      data={@data}
      locale={@locale}
    />
    """
  end

  defp title(%{assigns: %{live_action: :year, locale: locale}}, data),
    do: t(locale, "stats.show.statistics_for_year_year", %{year: data.year})

  defp title(%{assigns: %{live_action: :month, locale: locale}}, data),
    do:
      t(locale, "stats.month.month_year_monthly_digest", %{
        year: data.year,
        month: DawarichWeb.LocalizedDate.month_name(locale, data.year, data.month)
      })

  defp title(socket, _), do: t(socket.assigns.locale, "stats.index.statistics", %{})

  defp refuse_in_place(socket, :stale_session), do: NativeDataAuth.refuse(socket, :stale_session)
  defp refuse_in_place(socket, _), do: NativeDataAuth.refuse(socket, :invalid_input)
  defp command_options(socket), do: Keyword.put(options(socket), :now, DateTime.utc_now())

  defp fetch(socket, scope, opts) do
    read = fn fresh -> read(fresh, socket.assigns.live_action, socket.assigns.query, opts) end

    case Dawarich.Cache.Pages.fetch(
           scope,
           resource(socket),
           socket.assigns.query,
           read,
           Keyword.put(
             opts,
             :period_kind,
             if(socket.assigns.live_action == :month, do: :month, else: :year)
           )
         ) do
      {:error, :stale} ->
        with {:ok, fresh} <- NativeDataAuth.scope(socket),
             {:ok, data} <- read.(fresh),
             {:ok, current} <- NativeDataAuth.scope(socket),
             true <- fresh == current do
          {:ok, data}
        else
          false -> {:error, :stale}
          error -> error
        end

      result ->
        result
    end
  end

  defp resource(%{assigns: %{live_action: :index}}), do: :index
  defp resource(%{assigns: %{live_action: mode}}), do: mode
  defp read(scope, :index, params, opts), do: Pages.index(scope, params, opts)
  defp read(scope, :year, params, opts), do: Pages.year(scope, params, opts)
  defp read(scope, :month, params, opts), do: Pages.month(scope, params, opts)

  defp options(socket),
    do: [
      now: DateTime.utc_now(),
      self_hosted: socket.assigns.self_hosted,
      base_url: socket.assigns[:base_url] || ""
    ]
end
