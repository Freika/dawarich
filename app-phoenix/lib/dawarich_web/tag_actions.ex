defmodule DawarichWeb.TagActions do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.{Repo, Tags.Writes}
  alias DawarichWeb.{Locale, TagWriteResponse}
  alias DawarichWeb.Api.Body

  @impl true
  def init(action), do: action
  @impl true
  def call(conn, _action) do
    user = conn.assigns.current_user
    action = conn.assigns.map_write_action

    ctx = %{
      now: Map.get(conn.assigns, :now, DateTime.utc_now()),
      adopt_now: fn -> Map.get(conn.assigns, :now, DateTime.utc_now()) end,
      locale: Locale.resolve(nil, user, conn.assigns.rails_session)
    }

    ctx = Map.put(ctx, :render, &TagWriteResponse.prepare(conn, action, &1, ctx))
    attrs = conn.assigns.api_params["tag"] || %{}

    result =
      case action do
        :tag_create -> Writes.create(Repo, user, attrs, ctx)
        :tag_update -> Writes.update(Repo, user, id(conn), attrs, ctx)
        :tag_destroy -> Writes.destroy(Repo, user, id(conn), ctx)
      end

    case result do
      {status, %{response: response}} when status in [:ok, :invalid] ->
        TagWriteResponse.send(response)

      :rails ->
        Body.replay(conn, "tag write or response unsupported")
    end
  end

  defp id(conn), do: conn.request_path |> String.split("/") |> List.last() |> String.to_integer()
end
