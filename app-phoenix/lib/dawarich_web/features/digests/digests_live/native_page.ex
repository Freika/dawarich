defmodule DawarichWeb.DigestsLive.NativePage do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Digests.{Pages, Commands}
  alias DawarichWeb.NativeDataAuth
  alias DawarichWeb.DigestsLive.{NativeParts, NativeFullParts, NativeIndexParts}

  @impl true
  def mount(_, _, socket) do
    socket = %{socket | private: Map.put(socket.private, :digest_receipt, Ecto.UUID.generate())}

    {:ok,
     assign(socket,
       data: nil,
       query: %{},
       dialog: nil,
       share: nil,
       table: [],
       page_title: t(socket.assigns.locale, "users.digests.index.year_end_digests", %{})
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    query = Map.take(params, ~w(year page))
    socket = assign(socket, data: nil, query: query, dialog: nil, share: nil)

    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, data} <- read(scope, socket.assigns.live_action, query, options(socket)) do
      data =
        if socket.assigns.live_action == :show,
          do: Dawarich.Digests.PageWindow.prepare(data),
          else: data

      title =
        if socket.assigns.live_action == :show,
          do: t(scope.locale, "users.digests.show.year_year_in_review", %{year: data.year}),
          else: socket.assigns.page_title

      table =
        if socket.assigns.live_action == :show and not data.restricted,
          do: Dawarich.CountryNames.table(),
          else: []

      {:noreply, assign(socket, data: data, table: table, page_title: title)}
    else
      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(
           :alert,
           t(socket.assigns.locale, "controllers.users.digests.digest_not_found", %{})
         )
         |> redirect(to: "/digests")}

      {:error, reason} ->
        {:noreply, NativeDataAuth.refuse(socket, reason)}
    end
  end

  @impl true
  def handle_event("generate", %{"year" => year}, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, result} <-
           Commands.generate(
             scope,
             %{"year" => year},
             socket.private.digest_receipt,
             options(socket)
           ) do
      {:noreply, notice(socket, result)}
    else
      {:error, reason} -> {:noreply, error(socket, reason)}
    end
  end

  def handle_event("delete", _, socket) when socket.assigns.live_action == :show,
    do: {:noreply, assign(socket, :dialog, :delete)}

  def handle_event("cancel_delete", _, socket), do: {:noreply, assign(socket, :dialog, nil)}

  def handle_event("confirm_delete", _, socket) when socket.assigns.dialog == :delete do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, result} <- Commands.delete(scope, socket.assigns.query, options(socket)) do
      {:noreply, socket |> notice(result) |> redirect(to: "/digests")}
    else
      {:error, reason} -> {:noreply, error(socket, reason)}
    end
  end

  def handle_event("open_share", _, socket) when socket.assigns.live_action == :show do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, result} <-
           Dawarich.Sharing.report_controls(
             scope,
             %{type: :digest, owner_id: scope.user.id, year: socket.assigns.data.year},
             options(socket)
           ) do
      {:noreply, assign(socket, dialog: :share, share: result)}
    else
      {:error, reason} -> {:noreply, error(socket, reason)}
    end
  end

  def handle_event("close_share", _, socket),
    do: {:noreply, assign(socket, dialog: nil, share: nil)}

  def handle_event("share", %{"share" => attrs}, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         {:ok, result} <- Commands.share(scope, socket.assigns.query, attrs, options(socket)) do
      share = Map.put(result, :expiration, attrs["expiration"])
      {:noreply, assign(socket, share: share, dialog: :share)}
    else
      {:error, reason} -> {:noreply, error(socket, reason)}
    end
  end

  def handle_event("upgrade", _, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket), false <- socket.assigns.self_hosted do
      {:noreply,
       redirect(socket,
         external:
           DawarichWeb.StatsFormat.upgrade_url(
             scope.user,
             DateTime.utc_now(),
             false,
             "digest",
             "year_in_review"
           )
       )}
    else
      _ -> {:noreply, error(socket, :invalid_input)}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, error(socket, :invalid_input)}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-w-0 [&_.stat-title]:whitespace-normal [&_.stat-desc]:whitespace-normal [&_.card-body]:min-w-0 [&_.card-title]:flex-wrap [&_span]:[overflow-wrap:anywhere]">
      <NativeIndexParts.render :if={@data && @live_action == :index} data={@data} locale={@locale} />
      <nav :if={@data && @live_action == :index} class="flex flex-wrap gap-2">
        <.link :if={@data.page > 1} patch={"/digests?page=#{@data.page-1}"}>{t(
          @locale,
          "views.pagination.previous",
          %{}
        )}</.link>
        <.link :if={@data.more} patch={"/digests?page=#{@data.page+1}"}>{t(
          @locale,
          "views.pagination.next",
          %{}
        )}</.link>
      </nav>
      <div :if={@data && @live_action == :show} class="max-w-xl mx-auto my-5 min-w-0">
        <NativeParts.summary locale={@locale} digest={@data} unit={@data.unit} />
        <NativeFullParts.full
          :if={!@data.restricted}
          locale={@locale}
          digest={@data}
          unit={@data.unit}
          table={@table}
        />
        <section :if={@data.restricted} id="digest-upgrade" class="card bg-base-200 my-4">
          <h2 class="card-title flex-wrap">
            {t(@locale, "users.digests.show.want_more_insights", %{})}
          </h2>
          <p>
            {t(@locale, "users.digests.show.upgrade_to_pro_to_see_your_full_year_in_review", %{})}
          </p>
          <button class="btn btn-primary whitespace-normal" phx-click="upgrade">{t(
            @locale,
            "users.digests.show.upgrade_to_pro",
            %{}
          )}</button>
        </section>
        <nav class="flex flex-wrap min-w-0 gap-2">
          <.link
            :if={@data.period.page > 1}
            patch={"/digests/#{@data.year}?page=#{@data.period.page-1}"}
          >{t(@locale, "views.pagination.previous", %{})}</.link>
          <.link :if={@data.places_more} patch={"/digests/#{@data.year}?page=#{@data.period.page+1}"}>{t(
            @locale,
            "views.pagination.next",
            %{}
          )}</.link>
        </nav>
        <div class="flex flex-wrap min-w-0 gap-2">
          <.link class="btn whitespace-normal" navigate="/digests">{t(
            @locale,
            "users.digests.show.back_to_all_digests",
            %{}
          )}</.link>
          <button class="btn whitespace-normal" phx-click="open_share">{t(
            @locale,
            "users.digests.show.share",
            %{}
          )}</button>
          <button class="btn whitespace-normal" phx-click="delete">{t(
            @locale,
            "users.digests.show.delete",
            %{}
          )}</button>
        </div>
      </div>
      <DawarichWeb.DigestsLive.NativeDialogs.render
        dialog={@dialog}
        data={@data}
        share={@share}
        locale={@locale}
      />
    </main>
    """
  end

  defp read(scope, :index, query, opts), do: Pages.index(scope, query, opts)
  defp read(scope, :show, query, opts), do: Pages.get(scope, query, opts)

  defp options(socket),
    do: [
      now: DateTime.utc_now(),
      self_hosted: socket.assigns.self_hosted,
      base_url: socket.assigns.base_url
    ]

  defp notice(socket, result),
    do:
      put_flash(
        socket,
        :notice,
        t(socket.assigns.locale, "controllers.users.digests." <> result.notice, %{
          year: result.year
        })
      )

  defp error(socket, :stale_session), do: NativeDataAuth.refuse(socket, :stale_session)

  defp error(socket, :inactive),
    do:
      put_flash(
        socket,
        :alert,
        t(socket.assigns.locale, "controllers.application.your_account_is_not_active", %{})
      )

  defp error(socket, :invalid_input),
    do:
      put_flash(
        socket,
        :alert,
        t(socket.assigns.locale, "controllers.users.digests.invalid_year_selected", %{})
      )

  defp error(socket, :not_found),
    do:
      put_flash(
        socket,
        :alert,
        t(socket.assigns.locale, "controllers.users.digests.digest_not_found", %{})
      )

  defp error(socket, reason), do: NativeDataAuth.refuse(socket, reason, "/digests")
end
