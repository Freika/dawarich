defmodule DawarichWeb.DigestsLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view

  alias DawarichWeb.{
    DigestFullParts,
    DigestParts,
    Params,
    RailsWidgets,
    SharingParts,
    StatsFormat
  }

  @impl true
  def mount(params, _session, socket) do
    case page(socket.assigns.current_user, params, socket.assigns) do
      :not_found ->
        message = t(socket.assigns.locale, "controllers.users.digests.digest_not_found", %{})
        {:ok, socket |> put_flash(:alert, message) |> redirect(to: "/digests")}

      assigns ->
        {:ok, assign(socket, assigns)}
    end
  end

  @impl true
  def handle_event("rails_flash", params, socket),
    do: {:noreply, RailsWidgets.rails_flash(socket, params)}

  def page(user, %{"year" => year}, %{
        locale: locale,
        now: now,
        self_hosted: self_hosted,
        base_url: base_url
      }) do
    case Dawarich.Digests.get(user.id, Params.ruby_to_i(year)) do
      nil ->
        :not_found

      digest ->
        %{
          page_title: t(locale, "users.digests.show.year_year_in_review", %{year: digest.year}),
          rails_js: true,
          digest: digest,
          unit: StatsFormat.unit(user.settings),
          full: Dawarich.Entitlements.full_access?(user, self_hosted, now),
          table: Dawarich.CountryNames.table(),
          upgrade: StatsFormat.upgrade_url(user, now, self_hosted, "digest", "year_in_review"),
          sharing_url:
            if(digest.sharing_enabled and is_binary(digest.sharing_uuid),
              do: base_url <> "/shared/digest/" <> digest.sharing_uuid,
              else: ""
            )
        }
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto my-5">
      <DigestParts.summary locale={@locale} digest={@digest} unit={@unit} />
      <%= if @full do %>
        <DigestFullParts.full locale={@locale} digest={@digest} unit={@unit} table={@table} />
      <% else %>
        <DigestParts.upgrade locale={@locale} href={@upgrade} />
      <% end %>
      <DigestParts.actions locale={@locale} year={@digest.year} csrf={@rails_csrf_token} />
    </div>
    <SharingParts.sharing_dialog
      locale={@locale}
      scope="users.digests.show"
      hint="users.digests.show.allow_others_to_view_this_year_end_digest_auto_saves"
      action={"/digests/#{@digest.year}/sharing"}
      enabled={@digest.sharing_enabled}
      expiration={@digest.sharing_expiration || "24h"}
      url={@sharing_url}
      csrf={@rails_csrf_token}
    />
    """
  end
end
