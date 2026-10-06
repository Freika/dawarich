defmodule DawarichWeb.DemoDataActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Repo, DemoData.Importer}
  alias DawarichWeb.{SettingsActions, Locale, RailsSession, RequestURL, Translate}

  def init(action), do: action

  def call(conn, :demo_data, opts \\ []) do
    case SettingsActions.admit(conn, ~w(POST DELETE)) do
      :ok -> perform(conn, opts)
      {:error, status} -> SettingsActions.reject(conn, status)
    end
  end

  defp perform(conn, opts) do
    if conn.method == "DELETE" or
         String.upcase(conn.assigns.api_params["_method"] || "") == "DELETE" do
      case Dawarich.DemoData.Destroyer.call(Repo, conn.assigns.current_user) do
        :destroyed -> redirect(conn, "/", "demo_data_removed")
        :no_demo_data -> redirect(conn, "/", "no_demo_data_found")
        :error -> redirect(conn, "/", "something_went_wrong_removing_demo_data", "alert")
      end
    else
      create(conn, opts)
    end
  end

  defp create(conn, opts) do
    user = conn.assigns.current_user

    case Importer.call(Repo, user, opts) do
      :created -> redirect(conn, landing(user, opts), "demo_data_loaded")
      :exists -> redirect(conn, landing(user, opts), "demo_data_is_already_loaded")
      :error -> redirect(conn, "/", "something_went_wrong_loading_demo_data", "alert")
    end
  end

  defp landing(user, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    [[date]] =
      Repo.query!(
        "SELECT ($1::timestamptz AT TIME ZONE $2)::date - 1",
        [now, Importer.zone(user)],
        log: false
      ).rows

    {first, last} =
      Dawarich.Visits.Calendar.previous_day(Repo, Importer.zone(user), DateTime.to_unix(now))

    first = String.replace(first, "+00:00", "Z")
    last = last |> String.replace(~r/\.\d+/, "") |> String.replace("+00:00", "Z")

    "/map/v2?" <>
      URI.encode_query(%{
        "panel" => "timeline",
        "date" => Date.to_iso8601(date),
        "start_at" => first,
        "end_at" => last
      })
  end

  defp redirect(conn, path, key, type \\ "notice") do
    locale = Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
    message = Translate.t(locale, "controllers.settings.onboardings." <> key, %{})

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{type => message}}})
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
