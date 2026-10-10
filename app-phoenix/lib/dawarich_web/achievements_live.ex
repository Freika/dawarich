defmodule DawarichWeb.AchievementsLive do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Achievements.Collection
  alias DawarichWeb.{AchievementContext, AchievementIndex, AchievementDetail, AchievementModal}

  @impl true
  def mount(_, session, socket) do
    {:ok,
     socket
     |> assign(:achievement_initial, true)
     |> assign(
       :achievement_celebrations,
       DawarichWeb.AchievementSession.celebrations(session, get_connect_params(socket))
     )
     |> assign_new(:achievement_page, fn -> nil end)}
  end

  @impl true
  def handle_params(params, _, socket) do
    user = DawarichWeb.AchievementActions.Gate.current_user(socket.assigns.current_user)

    if is_nil(user) do
      {:noreply, redirect(socket, to: "/users/sign_in")}
    else
      context = AchievementContext.for_user(user, socket.assigns.locale)

      result =
        if socket.assigns.achievement_initial and not connected?(socket) and
             socket.assigns.achievement_page do
          {:ok, socket.assigns.achievement_page}
        else
          Collection.load(Dawarich.Repo, user.id, params, context)
        end

      case result do
        {:ok, view} ->
          view =
            if socket.assigns.achievement_initial,
              do: celebrations(view, socket.assigns.achievement_celebrations),
              else: view

          settings = Dawarich.UserSettings.get(user)
          threshold = DawarichWeb.Params.ruby_to_i(settings["min_minutes_spent_in_city"] || 60)

          {:noreply,
           assign(socket,
             view: view,
             query: Map.delete(params, "key"),
             current_user: user,
             threshold: threshold,
             page_title:
               if(view[:set],
                 do: view.set["name"],
                 else: t(socket.assigns.locale, "achievements.ui.title", %{})
               ),
             achievement_page: nil,
             achievement_initial: false,
             achievement_celebrations: []
           )}

        {:redirect, path} ->
          {:noreply, redirect(socket, to: path)}

        {:error, :not_found} ->
          {:noreply, redirect(socket, to: "/achievements")}
      end
    end
  end

  defp celebrations(view, keys) do
    mark = fn set -> Map.put(set, "celebrate", set["completed"] and set["key"] in keys) end

    if view[:set],
      do: Map.update!(view, :set, mark),
      else:
        view
        |> Map.update!(:sets, &Enum.map(&1, mark))
        |> Map.update!(:orphans, &Enum.map(&1, mark))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="phx-achievements"
      class="w-full my-5 ach-page"
      phx-hook="RailsStimulus"
      phx-update="ignore"
      data-controller="card-modal"
      data-action="turbo:before-cache@document->card-modal#prepareForCache"
      data-card-modal-labels-value={AchievementModal.labels(@locale)}
    >
      <%= if @view[:set] do %>
        <AchievementDetail.page
          view={@view}
          locale={@locale}
          csrf={@rails_csrf_token}
          threshold={@threshold}
          query={@query}
        />
      <% else %>
        <AchievementIndex.page view={@view} locale={@locale} />
      <% end %>
      <AchievementModal.modal locale={@locale} />
    </div>
    """
  end
end
