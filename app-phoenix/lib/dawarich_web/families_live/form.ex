defmodule DawarichWeb.FamiliesLive.Form do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.FamilyForms, only: [new_family: 1, lapsed_family: 1, edit_family: 1]

  @impl true
  def mount(_params, _session, socket) do
    action = socket.assigns.live_action

    case Dawarich.FamilyPage.read(socket.assigns.current_user, action,
           now: socket.assigns.now,
           self_hosted: socket.assigns.self_hosted
         ) do
      {:ok, page} ->
        content = if(page.state == :lapsed, do: "renew_family", else: "create_family")

        href =
          if (page.state in [:upgrade, :lapsed] and page.owner?) or page.state == :upgrade,
            do: upgrade(socket.assigns.current_user, socket.assigns.now, content),
            else: nil

        key =
          if(action == :edit,
            do: "families.edit.editing_family",
            else:
              if(page.state == :lapsed,
                do: "families.lapsed.family",
                else: "families.new.new_family"
              )
          )

        {:ok,
         assign(socket,
           page: page,
           upgrade_href: href,
           page_title: t(socket.assigns.locale, key, %{}),
           rails_js: true
         )}

      {:redirect, path, reason} ->
        {:ok,
         redirect(socket, to: path, status: if(reason == :not_authorized, do: 303, else: 302))}

      _other ->
        {:ok, redirect(socket, to: socket.assigns.request_path)}
    end
  end

  @impl true
  def handle_event("rails_flash", params, socket),
    do: {:noreply, DawarichWeb.RailsWidgets.rails_flash(socket, params)}

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="family-form-shell"
      class="contents"
      phx-hook="RailsStimulus"
      phx-update="ignore"
      data-turbo="true"
    >
      <.new_family
        :if={@page.state in [:create, :upgrade]}
        page={@page}
        locale={@locale}
        upgrade_href={@upgrade_href}
        rails_csrf_token={@rails_csrf_token}
      />
      <.lapsed_family
        :if={@page.state == :lapsed}
        page={@page}
        locale={@locale}
        upgrade_href={@upgrade_href}
        now={@now}
        rails_csrf_token={@rails_csrf_token}
      />
      <.edit_family
        :if={@page.state == :edit}
        page={@page}
        locale={@locale}
        rails_csrf_token={@rails_csrf_token}
      />
    </div>
    """
  end

  defp upgrade(user, now, content) do
    Dawarich.SubscriptionToken.url(user, now, plan: "family", interval: "annual") <>
      "&" <>
      DawarichWeb.Params.to_query(%{
        "utm_source" => "app",
        "utm_medium" => "family",
        "utm_campaign" => "family_upgrade",
        "utm_content" => content
      })
  end
end
