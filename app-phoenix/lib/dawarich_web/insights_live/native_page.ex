defmodule DawarichWeb.InsightsLive.NativePage do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Insights.{Pages, ResidencyPage}
  alias Dawarich.Stats.PageRefresh
  alias DawarichWeb.{DataAsync, NativeDataAuth}
  alias DawarichWeb.InsightsLive.NativeParts

  @impl true
  def mount(_, _, socket) do
    if connected?(socket),
      do:
        Phoenix.PubSub.subscribe(
          Dawarich.PubSub,
          PageRefresh.topic(socket.private.data_principal.actor_id)
        )

    {:ok,
     assign(socket,
       data: nil,
       query: %{},
       details: nil,
       residency: nil,
       refresh_state: nil,
       page_title: t(socket.assigns.locale, "insights.index.insights", %{})
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    socket =
      socket
      |> DataAsync.advance()
      |> assign(
        data: nil,
        details: nil,
        residency: nil,
        refresh_state: nil,
        query: Map.take(params, ~w(year month page residency_page))
      )

    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, data} <- Pages.overview(scope, socket.assigns.query, options(socket)) do
      page = data.period.page

      data =
        data
        |> Map.put(:more, length(data.available) > page * 50)
        |> Map.put(:available, Enum.slice(data.available, (page - 1) * 50, 50))
        |> Map.put(:locked, Enum.slice(data.locked, (page - 1) * 50, 50))

      query =
        socket.assigns.query
        |> Map.put("year", data.selected)
        |> Map.put("month", to_string(data[:selected_month] || ""))

      socket = assign(socket, data: data, query: query)

      if data.year_locked or data.restricted do
        {:noreply,
         assign(socket, details: %{state: :restricted}, residency: %{state: :restricted})}
      else
        socket = refresh(socket, scope, false)
        {:noreply, socket |> start(:details) |> start(:residency)}
      end
    else
      {:error, reason} -> {:noreply, NativeDataAuth.refuse(socket, reason)}
    end
  end

  @impl true
  def handle_async(run, result, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, _, period} <-
           Dawarich.Analytics.Period.admit(
             scope,
             socket.assigns.query,
             :insights,
             options(socket)
           ) do
      if Map.take(period, [:restricted, :zone, :unit, :cutoff]) !=
           Map.take(socket.assigns.data.period, [:restricted, :zone, :unit, :cutoff]) do
        handle_params(socket.assigns.query, "", socket)
      else
        case DataAsync.finish(socket, run, result) do
          {:ok, data, socket} ->
            {:noreply, assign(socket, elem(run, 0), %{state: data.state, value: data})}

          {:stale, socket} ->
            {:noreply, socket}

          {:error, reason, socket} ->
            {:noreply, failed(socket, elem(run, 0), reason)}
        end
      end
    else
      {:error, reason} -> {:noreply, NativeDataAuth.refuse(socket, reason)}
    end
  end

  @impl true
  def handle_info({:data_read_timeout, run}, socket) do
    case DataAsync.timeout(socket, run) do
      {:stale, socket} ->
        {:noreply, socket}

      {:error, reason, socket} ->
        {:noreply, failed(cancel_async(socket, run), elem(run, 0), reason)}
    end
  end

  def handle_info({:analytics_ready, _, _}, socket),
    do: handle_params(socket.assigns.query, "", socket)

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("period", %{"period" => params}, socket),
    do:
      {:noreply,
       push_patch(socket,
         to: path(socket) <> "?" <> URI.encode_query(Map.take(params, ~w(year month)))
       )}

  def handle_event("retry_read", %{"kind" => kind}, socket) when kind in ~w(details residency),
    do: {:noreply, start(socket, if(kind == "details", do: :details, else: :residency))}

  def handle_event("retry_refresh", _, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         do: {:noreply, refresh(socket, scope, true) |> start(:details)}
  end

  def handle_event("upgrade", _, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket), false <- socket.assigns.self_hosted do
      {:noreply,
       redirect(socket,
         external:
           Dawarich.NativeM5.Dependencies.insights_upgrade_url(scope, DateTime.utc_now(), false)
       )}
    else
      _ -> {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="w-full min-w-0 my-5">
      <h1 class="text-3xl font-bold break-words">{@page_title}</h1>
      <NativeParts.overview
        :if={@data}
        data={@data}
        query={@query}
        locale={@locale}
        path={if(@live_action == :details, do: "/insights/details", else: "/insights")}
      />
      <p
        :if={@data && (@data.year_locked || @data.restricted)}
        id="insights-locked"
        role="status"
        class="alert flex-wrap min-w-0 break-words"
      >
        {t(@locale, "stats.locked_year_card.available_on_pro", %{})}
      </p>
      <button
        :if={@data && @data.restricted}
        id="insights-upgrade"
        class="btn whitespace-normal"
        phx-click="upgrade"
      >{t(@locale, "shared.plan_data_window_alert.upgrade_to_pro", %{})}</button>
      <NativeParts.read
        :if={@details}
        kind="details"
        read={@details}
        locale={@locale}
        query={@query}
        path={if(@live_action == :details, do: "/insights/details", else: "/insights")}
      />
      <NativeParts.read
        :if={@residency}
        kind="residency"
        read={@residency}
        locale={@locale}
        query={@query}
        path={if(@live_action == :details, do: "/insights/details", else: "/insights")}
      />
      <p
        :if={@refresh_state == :pending || (@details && @details.state == :pending)}
        id="insights-refresh-pending"
        role="status"
        aria-live="polite"
      >
        {t(@locale, "javascript.common.loading", %{})}
      </p>
      <button :if={@refresh_state == :failed} class="btn whitespace-normal" phx-click="retry_refresh">{t(
        @locale,
        "javascript.messages.retry",
        %{}
      )}</button>
    </main>
    """
  end

  defp start(socket, :residency) when socket.assigns.data.all_time, do: socket

  defp start(socket, kind) do
    if (connected?(socket) and socket.assigns.data) && !socket.assigns.data.restricted do
      inputs = {socket.assigns.query, options(socket)}

      default =
        case kind do
          :details -> &__MODULE__.details/2
          :residency -> &__MODULE__.residency/2
        end

      reader = Application.get_env(:dawarich, :native_insights_readers, %{})[kind] || default

      socket
      |> assign(kind, %{state: :loading})
      |> DataAsync.start(
        kind,
        :crypto.hash(:sha256, :erlang.term_to_binary(inputs)),
        inputs,
        reader
      )
    else
      socket
    end
  end

  def details(scope, {params, opts}),
    do:
      Dawarich.Cache.Pages.fetch(scope, :insights, params, &Pages.details(&1, params, opts), opts)

  def residency(scope, {params, opts}), do: ResidencyPage.load(scope, params, opts)

  defp refresh(socket, scope, retry) do
    result =
      if retry,
        do: PageRefresh.retry(scope, :insights, socket.assigns.query, options(socket)),
        else: PageRefresh.request(scope, :insights, socket.assigns.query, options(socket))

    state =
      case result do
        {:ok, %{state: state}} -> state
        _ -> :failed
      end

    assign(socket, :refresh_state, state)
  end

  defp failed(socket, _, :stale_session), do: NativeDataAuth.refuse(socket, :stale_session)
  defp failed(socket, kind, _), do: assign(socket, kind, %{state: :failed})

  defp path(socket),
    do: if(socket.assigns.live_action == :details, do: "/insights/details", else: "/insights")

  defp options(socket), do: [now: DateTime.utc_now(), self_hosted: socket.assigns.self_hosted]
end
