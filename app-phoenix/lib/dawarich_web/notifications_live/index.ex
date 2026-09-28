defmodule DawarichWeb.NotificationsLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok,
       assign(
         socket,
         :page_title,
         t(socket.assigns.locale, "notifications.index.notifications", %{})
       )}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full my-5">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
        <h1 class="text-3xl font-bold">{t(@locale, "notifications.index.notifications", %{})}</h1>
      </div>
    </div>
    """
  end
end
