defmodule DawarichWeb.SharingLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view
  alias DawarichWeb.{NativeSharingAuth, SharingResource, SharingNativeForm, SharingNativeActive}
  @impl true
  def mount(_, _, socket),
    do: {:ok, assign(socket, errors: [], form_values: %{}, confirmation: nil)}

  @impl true
  def handle_params(_, _, socket), do: {:noreply, socket}
  @impl true
  def handle_info(_, socket), do: {:noreply, socket}
  @impl true
  def handle_event("report_sharing_update", attrs, socket) when is_map(attrs) do
    result =
      Dawarich.Sharing.change(
        socket.assigns.current_scope,
        socket.assigns.resource,
        :update,
        Map.take(attrs, ~w(enabled expiration))
      )

    socket = reload(socket)

    case result do
      {:ok, _} ->
        {:noreply, assign(socket, errors: [])}

      _ ->
        {:noreply,
         assign(socket, errors: [t(socket.assigns.locale, "errors.messages.invalid", %{})])}
    end
  end

  def handle_event("sharing_create", %{"shared_link" => attrs}, socket) when is_map(attrs) do
    values =
      Map.take(attrs, ~w(name expires_at start_date end_date audience))
      |> Map.filter(fn {_, v} -> is_binary(v) and byte_size(v) <= 4096 end)

    settings =
      if is_map(attrs["settings"]),
        do:
          Map.take(
            attrs["settings"],
            ~w(show_route show_stats show_days show_day_notes show_description show_photos)
          )
          |> Map.filter(fn {_, v} -> v in ["0", "1", true, false] end),
        else: %{}

    values = Map.put(values, "settings", settings)

    {:noreply,
     change(assign(socket, form_values: values), socket.assigns.resource, :create, %{
       "shared_link" => attrs
     })}
  end

  def handle_event("sharing_prepare", params, socket) do
    action =
      case params["action"] do
        "regenerate" -> :regenerate
        "regenerate_phrase" -> :regenerate_phrase
        "revoke" -> :revoke
        "destroy" -> :destroy
        _ -> nil
      end

    resource =
      if is_binary(params["id"]),
        do: %{type: :shared, owner_id: socket.assigns.current_user.id, id: params["id"]},
        else: socket.assigns.resource

    if not is_nil(action) and
         match?({:ok, _}, Dawarich.Sharing.page(socket.assigns.current_scope, resource)) do
      {:noreply, assign(socket, confirmation: %{resource: resource, action: action})}
    else
      {:noreply,
       assign(socket,
         confirmation: nil,
         errors: [t(socket.assigns.locale, "errors.messages.invalid", %{})]
       )}
    end
  end

  def handle_event("sharing_cancel", _, socket), do: {:noreply, assign(socket, confirmation: nil)}

  def handle_event(
        "sharing_confirm",
        _,
        %{assigns: %{confirmation: %{resource: resource, action: action}}} = socket
      ),
      do: {:noreply, change(assign(socket, confirmation: nil), resource, action, %{})}

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp change(socket, resource, action, attrs) do
    result = Dawarich.Sharing.change(socket.assigns.current_scope, resource, action, attrs)
    socket = push_event(socket, "sharing-clear", %{})

    case result do
      {:ok, _} ->
        reload(assign(socket, errors: [], form_values: %{}))
        |> put_flash(:notice, notice(socket, action))

      {:error, %{errors: errors}} ->
        reload(
          assign(socket,
            errors:
              Enum.map(errors, fn
                {_field, text} -> text
                text -> text
              end)
          )
        )

      {:error, _} ->
        reload(assign(socket, errors: [t(socket.assigns.locale, "errors.messages.invalid", %{})]))
    end
  end

  defp reload(socket) do
    case NativeSharingAuth.authorize(socket) do
      {_, socket} -> socket
    end
  end

  defp notice(socket, action) do
    key =
      case action do
        :create -> "created"
        :regenerate -> "url_regenerated"
        :regenerate_phrase -> "magic_phrase_regenerated"
        :revoke -> "revoked"
        :destroy -> "deleted"
      end

    t(socket.assigns.locale, "controllers.concerns.share_links.managable." <> key, %{})
  end

  defp selected(page, %{type: :hub}, "live"), do: page.live
  defp selected(page, %{type: :hub}, "timeline"), do: page.timeline
  defp selected(_page, %{type: :hub}, _), do: nil
  defp selected(page, _, _), do: page[:share]

  defp heading(locale, base) do
    if base.type in [:month, :digest, :achievement],
      do: t(locale, "stats.month.share", %{}),
      else:
        if(base.type == :hub,
          do: t(locale, "share_links.hubs.frame.share", %{}),
          else: t(locale, "shared_links.modal_#{base.type}_create_form.create_share_link", %{})
        )
  end

  defp confirmation_key(:regenerate),
    do: "shared_links.modal_active.generate_a_new_url_the_current_url_will_stop_working"

  defp confirmation_key(:regenerate_phrase), do: "shared_links.modal_active.generate_a_new_phrase"

  defp confirmation_key(_),
    do: "shared_links.modal_active.revoke_this_link_it_will_stop_working_immediately"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, share: selected(assigns.page, assigns.base_resource, assigns.tab))

    ~H"""
    <section
      id="native-sharing"
      class="w-full max-w-3xl mx-auto my-5 min-w-0 [overflow-wrap:anywhere]"
    >
      <header class="flex flex-wrap items-center justify-between gap-3 mb-4">
        <h1 class="text-2xl font-bold min-w-0">{heading(@locale, @base_resource)}</h1>
        <a
          href={SharingResource.back(@base_resource)}
          class="btn btn-ghost btn-sm h-auto whitespace-normal"
        >{t(@locale, "shared_links.modal_live_create_form.cancel", %{})}</a>
      </header>
      <p :for={error <- @errors} role="alert" class="alert alert-error mb-3">{error}</p>
      <nav :if={@base_resource.type == :hub} role="tablist" class="flex flex-wrap gap-2 mb-4">
        <.link
          :for={
            {tab, key} <- [
              {"live", "live_location"},
              {"timeline", "time_period"},
              {"make", "make_something"},
              {"shared", "shared"}
            ]
          }
          patch={"/share_links/hub?" <> Plug.Conn.Query.encode(Map.put(@query_params || %{},"tab",tab))}
          role="tab"
          aria-selected={@tab == tab}
          data-testid={"hub-tab-#{tab}"}
          class="btn btn-outline btn-sm h-auto whitespace-normal"
        >
          {t(@locale, "share_links.hubs.body." <> key, %{})}
        </.link>
      </nav>
      <%= cond do %>
        <% @base_resource.type in [:month, :digest, :achievement] -> %>
          <DawarichWeb.SharingNativeReport.form
            resource={@base_resource}
            page={@page}
            locale={@locale}
          />
        <% @base_resource.type == :hub and @tab == "make" -> %>
          <div class="flex flex-wrap gap-3">
            <a
              :for={type <- ~w(video poster)}
              href={"/map/v2?studio=" <> type}
              class="btn btn-outline h-auto whitespace-normal"
              data-testid={"hub-make-#{type}"}
            >{t(@locale, "share_links.hubs.body.make_#{type}", %{})}</a>
          </div>
        <% @base_resource.type == :hub and @tab == "shared" -> %>
          <article
            :for={share <- @page.shares}
            data-share-id={share.id}
            class="border rounded-xl p-4 mb-3 min-w-0"
          >
            <h2 class="font-bold">{share.name}</h2>
            <SharingNativeActive.active share={share} locale={@locale} list={true} />
          </article>
        <% @share != nil -> %>
          <SharingNativeActive.active share={@share} locale={@locale} />
        <% true -> %>
          <SharingNativeForm.form
            resource={@resource}
            page={@page}
            locale={@locale}
            values={@form_values}
            user={@current_user}
          />
      <% end %>
      <dialog
        :if={@confirmation}
        id="sharing-confirm"
        phx-hook="SharingDialog"
        data-pending="true"
        class="modal"
      >
        <div class="modal-box min-w-0 [overflow-wrap:anywhere]">
          <p>
            {t(
              @locale,
              confirmation_key(@confirmation.action),
              %{}
            )}
          </p>
          <div class="modal-action flex flex-wrap">
            <button
              type="button"
              phx-click="sharing_cancel"
              class="btn btn-ghost h-auto whitespace-normal"
            >{t(@locale, "shared_links.modal_live_create_form.cancel", %{})}</button>
            <button
              type="button"
              phx-click="sharing_confirm"
              phx-disable-with={t(@locale, "javascript.common.confirm", %{})}
              class="btn btn-warning h-auto whitespace-normal"
            >{t(@locale, "javascript.common.confirm", %{})}</button>
          </div>
        </div>
      </dialog>
    </section>
    """
  end
end
