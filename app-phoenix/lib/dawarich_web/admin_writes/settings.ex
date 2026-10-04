defmodule DawarichWeb.AdminWrites.Settings do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Admin.{InstanceWrites, SettingWrites}
  alias Dawarich.I18n
  alias DawarichWeb.AdminWrites.{Request, Response}
  alias DawarichWeb.RailsProxy
  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.fetch!(opts, :action)

    case Request.load(conn, action, opts) do
      {:ok, conn, actor, params, context} -> dispatch(conn, actor, params, context)
      {:handoff, %{halted: true} = conn} -> conn
      {:handoff, conn} -> proxy(conn)
    end
  end

  defp dispatch(conn, actor, params, %{action: :registration} = context) do
    case SettingWrites.registration(actor, params, context) do
      {:ok, value} ->
        status = if value == true, do: "enabled", else: "disabled"

        {:ok, message} =
          I18n.t(
            context.locale,
            "controllers.settings.users.user_registration_has_been_status",
            %{"status" => status}
          )

        Response.redirect(conn, 302, "/settings/users", :notice, message)

      {:handoff, _} ->
        proxy(conn)

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
        proxy(conn)

      {:terminal, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end

  defp dispatch(conn, actor, params, %{action: :instance} = context) do
    ordered = Enum.map(context.form_order, &{&1, params[&1]})

    input = %{
      "instance_settings" => nested(ordered, "instance_settings"),
      "instance_settings_clear" => Map.new(nested(ordered, "instance_settings_clear"))
    }

    section = params["section"]

    suffix =
      if section in ~w(photon geoapify nominatim locationiq rate_limit points),
        do: "?" <> URI.encode_query(%{"section" => section}),
        else: ""

    path = "/admin/settings" <> suffix

    case InstanceWrites.call(actor, input, context) do
      {:ok, []} ->
        {:ok, message} = I18n.t(context.locale, "admin.settings.update.saved")
        Response.redirect(conn, 303, path, :notice, message)

      {:ok, refused} ->
        {:ok, message} =
          I18n.t(context.locale, "admin.settings.update.pinned", %{
            "variables" => Enum.join(refused, ", ")
          })

        Response.redirect(conn, 303, path, :alert, message)

      {:invalid, message} ->
        Response.redirect(conn, 303, path, :alert, message)

      {:handoff, _} ->
        proxy(conn)

      {:terminal, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end

  defp nested(ordered, prefix) do
    for {field, value} <- ordered,
        String.starts_with?(field, prefix <> "["),
        do:
          {field |> String.replace_prefix(prefix <> "[", "") |> String.trim_trailing("]"), value}
  end

  defp proxy(conn), do: RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
end
