defmodule DawarichWeb.Api.PhotosController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.{Accounts, I18n}
  alias Dawarich.Photos.{Index, Thumbnail}
  alias DawarichWeb.Api.{Body, Respond}

  @sources ~w(immich photoprism)
  @printable ~r/\A[\x20-\x7E]*\z/

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :index) do
    case Index.fetch(conn.assigns.api_user, conn.assigns.api_params) do
      {:ok, photos, errors} ->
        conn =
          if errors == [],
            do: conn,
            else: Plug.Conn.put_resp_header(conn, "x-photo-source-errors", Enum.join(errors, ","))

        Respond.json(conn, 200, photos)

      {:unconfigured, source} ->
        unconfigured(conn, source)

      {:error, _} ->
        error(conn, 502, "controllers.api.v1.photos.failed_to_fetch_photos")
    end
  end

  def call(conn, :thumbnail) do
    case read(conn.assigns.api_user, conn.assigns.api_params["source"], conn.path_params["id"]) do
      {:ok, image} ->
        Respond.data(conn, image, "image/jpeg", cache_control: "max-age=1800, private")

      {:unconfigured, source} ->
        unconfigured(conn, source)

      {:error, status} ->
        error(conn, status, "services.immich.response_analyzer.thumbnail_failed")

      :timeout ->
        error(conn, 502, "controllers.api.v1.photos.failed_to_fetch_photos")

      {:replay, reason} ->
        Body.replay(conn, reason)
    end
  end

  defp read(user, source, id) do
    settings = Accounts.settings(user.id)

    cond do
      not is_map(settings) ->
        {:replay, "settings shape"}

      not (is_nil(source) or (is_binary(source) and source =~ @printable)) ->
        {:replay, "source parameter shape"}

      not Thumbnail.configured?(settings) or source not in @sources ->
        {:unconfigured, source}

      true ->
        Thumbnail.fetch(settings, source, id)
    end
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end

  defp unconfigured(conn, source) do
    {:ok, message} =
      I18n.t("en", "controllers.api.v1.photos.capitalize_integration_not_configured", %{
        "source" => source && String.capitalize(source)
      })

    Respond.json(conn, 401, {:object, [{"error", message}]})
  end

  defp error(conn, status, key),
    do: Respond.json(conn, status, {:object, [{"error", I18n.en!(key)}]})
end
