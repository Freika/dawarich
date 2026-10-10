defmodule DawarichWeb.AdminWrites.Settings do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Admin.SettingWrites
  alias Dawarich.I18n
  alias DawarichWeb.AdminWrites.{Request, Response}
  alias DawarichWeb.AdminWrites.Fallback
  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)

    case Request.load(conn, action, opts) do
      {:ok, conn, actor, params, context} -> dispatch(conn, actor, params, context)
      {:handoff, %{halted: true} = conn} -> conn
      {:handoff, conn} -> Fallback.call(conn, opts)
    end
  end

  defp dispatch(conn, actor, params, %{action: :background, method: "POST"} = context) do
    case Dawarich.Admin.BackgroundCommands.call(actor, params["job_name"], context) do
      {:ok, path} ->
        {:ok, message} =
          I18n.t(
            context.locale,
            "controllers.settings.background_jobs.job_was_successfully_created"
          )

        Response.redirect(conn, 302, path, :notice, message)

      {:handoff, _} ->
        Fallback.call(conn, action: :background, context: context)

      {:invalid, _} ->
        Fallback.call(conn, action: :background, context: context)

      {:terminal, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end

  defp dispatch(conn, actor, params, %{action: :background} = context) do
    input =
      if Map.has_key?(params, "settings[visits_suggestions_enabled]"),
        do: %{"visits_suggestions_enabled" => params["settings[visits_suggestions_enabled]"]},
        else: %{}

    case SettingWrites.background(actor, input, context) do
      {:ok, _} ->
        {:ok, message} =
          I18n.t(context.locale, "controllers.settings.background_jobs.settings_updated")

        Response.redirect(conn, 302, "/settings/background_jobs", :notice, message)

      {:handoff, _} ->
        Fallback.call(conn, action: context.action, context: context)

      {:terminal, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end
end
