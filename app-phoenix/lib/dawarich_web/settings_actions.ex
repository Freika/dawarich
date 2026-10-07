defmodule DawarichWeb.SettingsActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Accounts, Repo, Settings.General}
  alias DawarichWeb.{Locale, RailsForm, RailsSession, RequestURL, Translate}

  def init(action), do: action
  def enabled?(_conn, _params), do: Dawarich.Standalone.enabled?()

  def call(conn, :update) do
    case admit(conn, ~w(PATCH PUT), locale: true) do
      :ok ->
        case General.save(Repo, conn.assigns.current_user.id, conn.assigns.api_params) do
          {:ok, settings} ->
            conn = assign(conn, :current_user, %{conn.assigns.current_user | settings: settings})

            conn =
              if settings["locale"],
                do: RailsSession.stage(conn, %{"locale" => settings["locale"]}),
                else: conn

            redirect(conn, "/settings/general", "settings_updated")

          {:error, :save_failed} ->
            reject(conn, 500)

          {:error, _} ->
            redirect(conn, "/settings/general", "failed_to_update_settings", "alert")
        end

      {:error, status} ->
        reject(conn, status)
    end
  end

  def admit(conn, methods, opts \\ []) do
    params = conn.assigns.api_params
    override = params["_method"]

    method =
      if conn.method == "POST" and is_binary(override),
        do: String.upcase(override),
        else: conn.method

    check =
      if opts[:locale], do: assign(conn, :api_params, Map.delete(params, "locale")), else: conn

    cond do
      is_nil(conn.assigns.current_user) ->
        {:error, 302}

      method not in methods ->
        {:error, 404}

      conn.assigns.api_query != %{} ->
        {:error, 422}

      method == "GET" ->
        if match?(
             %Accounts.User{},
             Accounts.from_session(conn.assigns.rails_session, DateTime.utc_now())
           ),
           do: :ok,
           else: {:error, 302}

      RailsForm.admission(check,
        allowed_overrides: methods,
        per_form: opts[:per_form],
        csrf_method: method
      ) != :ok ->
        {:error, 422}

      true ->
        :ok
    end
  end

  def reject(conn, 302),
    do: conn |> put_resp_header("location", "/users/sign_in") |> send_resp(302, "") |> halt()

  def reject(conn, status), do: conn |> send_resp(status, "") |> halt()

  def redirect(conn, path, key, type \\ "notice", bindings \\ %{}) do
    locale = Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
    message = Translate.t(locale, "controllers.settings.general." <> key, bindings)

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{type => message}}})
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
