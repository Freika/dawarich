if Application.compile_env(:dawarich, :reference_live, false) do
  defmodule DawarichWeb.ReferenceLive do
    @moduledoc false
    use DawarichWeb, :live_view

    @impl true
    def mount(_params, _session, socket), do: {:ok, assign(socket, :count, 0)}

    @impl true
    def handle_event("bump", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}

    @impl true
    def render(assigns) do
      ~H"""
      <div id="reference">
        <p id="reference-user">
          {if @current_user, do: @current_user.email, else: t(@locale, "shared.navbar.login", %{})}
        </p>
        <button id="reference-bump" type="button" class="btn" phx-click="bump">{@count}</button>
      </div>
      """
    end
  end
end
