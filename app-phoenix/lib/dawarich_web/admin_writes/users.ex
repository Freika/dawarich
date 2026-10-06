defmodule DawarichWeb.AdminWrites.Users do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Admin.{UserCreate, UserSecurity, UserUpdate}
  alias Dawarich.I18n
  alias DawarichWeb.AdminWrites.{Request, Response}
  alias DawarichWeb.AdminWrites.Fallback

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.get(opts, :action, :create)

    case Request.load(conn, action, opts) do
      {:ok, conn, actor, params, context} ->
        dispatch(conn, actor, params, context)

      {:handoff, %{halted: true} = conn} ->
        conn

      {:handoff, conn} ->
        Fallback.call(conn, opts)
    end
  end

  defp dispatch(conn, actor, params, %{action: :create} = context) do
    input =
      Map.new(
        for {key, value} <- params,
            String.starts_with?(key, "user["),
            do: {String.slice(key, 5..-2//1), value}
      )

    case UserCreate.call(actor, input, context) do
      {:ok, _id} ->
        {:ok, message} =
          I18n.t(context.locale, "controllers.settings.users.user_was_successfully_created")

        Response.redirect(conn, 302, "/settings/users", :notice, message)

      {:invalid, message} ->
        Response.redirect(conn, 303, "/settings/users", :alert, message)

      {:handoff, _} ->
        Fallback.call(conn, action: context.action, context: context)

      {:terminal, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end

  defp dispatch(conn, actor, params, %{action: :update} = context) do
    id = conn.request_path |> String.split("/") |> List.last() |> String.to_integer()

    input =
      Map.new(
        for {key, value} <- params,
            String.starts_with?(key, "user["),
            do: {String.slice(key, 5..-2//1), value}
      )

    case UserUpdate.call(actor, id, input, context) do
      {:ok, _id} ->
        {:ok, message} =
          I18n.t(context.locale, "controllers.settings.users.user_was_successfully_updated")

        Response.redirect(conn, 302, "/settings/users", :notice, message)

      {:invalid, message} ->
        Response.redirect(conn, 303, "/settings/users", :alert, message)

      {:blocked, message} ->
        Response.redirect(conn, 302, "/settings/users", :alert, message)

      {:handoff, _} ->
        Fallback.call(conn, action: context.action, context: context)

      {:terminal, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end

  defp dispatch(conn, actor, _params, %{action: :destroy} = context) do
    id = conn.request_path |> String.split("/") |> List.last() |> String.to_integer()
    DawarichWeb.AdminUserDestroy.respond(conn, actor, id, context)
  end

  defp dispatch(conn, actor, _params, %{action: action} = context)
       when action in [:rotate, :reset] do
    id = conn.request_path |> String.split("/") |> Enum.at(-2) |> String.to_integer()

    case apply(UserSecurity, action, [actor, id, context]) do
      {:ok, _id} ->
        {:ok, message} =
          I18n.t(
            context.locale,
            "controllers.settings.users." <>
              if(action == :reset,
                do: "password_reset_email_has_been_sent",
                else: "api_key_has_been_regenerated"
              )
          )

        Response.redirect(conn, 302, "/settings/users/#{id}", :notice, message)

      {:handoff, reason} ->
        Fallback.call(conn,
          action: context.action,
          context: context,
          status: if(reason == :target, do: 404, else: 422)
        )

      {:terminal, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end
end
