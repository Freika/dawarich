defmodule DawarichWeb.PlaceStreams do
  @moduledoc false
  use Phoenix.Component
  alias DawarichWeb.{Chrome, PlaceDrawerFrame}
  alias Dawarich.PlacesApi.Payload
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def render(action, context) do
    data = if action == :create or (action == :update and not context.framed), do: data(context)

    stream(Map.merge(context, %{__changed__: nil, action: action, data: data}))
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp data(ctx) do
    [{:object, pairs}] = Payload.places(ctx.user.id, "p.id=$2", [ctx.id], "", ctx.repo)

    pairs =
      for {key, value} <- pairs,
          key not in ~w(name_locked created_at),
          do:
            {key,
             if(key == "tags",
               do:
                 Enum.map(value, fn {:object, tag} ->
                   {:object, Enum.reject(tag, fn {k, _} -> k == "privacy_radius_meters" end)}
                 end),
               else: value
             )}

    Ruby.json({:object, pairs}) |> IO.iodata_to_binary()
  end

  defp stream(assigns) do
    ~H"""
    <turbo-stream :if={@data} action="replace" target="place-creation-data">
      <template><div
        id="place-creation-data"
        data-place={@data}
        data-created={to_string(@action == :create)}
        data-updated={to_string(@action == :update)}
        class="hidden"
      >
      </div></template>
    </turbo-stream>
    <turbo-stream :if={@action == :update} action="update" target="place-drawer">
      <template><PlaceDrawerFrame.drawer drawer={@drawer} locale={@locale} csrf={@csrf} /></template>
    </turbo-stream>
    <turbo-stream action="append" target="flash-messages">
      <template><Chrome.flash_message
        type={if @action == :error, do: "error", else: "success"}
        message={@message}
        locale={@locale}
      /></template>
    </turbo-stream>
    """
  end
end
