defmodule DawarichWeb.AdminUserDestroy do
  @moduledoc false
  alias Dawarich.Auth.AccountDestroy
  alias Dawarich.I18n
  alias DawarichWeb.AdminWrites.{Fallback, Request, Response}

  def init(opts), do: opts

  def call(conn, opts) do
    case Request.load(conn, :destroy, opts) do
      {:ok, conn, actor, _params, context} ->
        id = conn.request_path |> String.split("/") |> List.last() |> String.to_integer()
        respond(conn, actor, id, context)

      {:handoff, %{halted: true} = conn} ->
        conn

      {:handoff, conn} ->
        Fallback.call(conn, Keyword.put(opts, :action, :destroy))
    end
  end

  def respond(conn, actor, id, context) do
    context = Map.merge(Application.get_env(:dawarich, :account_destroy_context, %{}), context)

    case AccountDestroy.request_as_admin(actor.id, id, context) do
      {:ok, :scheduled} ->
        message = text(context, "user_deletion_has_been_initiated_the_account_will_be_fully")
        Response.redirect(conn, 302, "/settings/users", :notice, message)

      {:error, :cannot_delete_account} ->
        message = text(context, "cannot_delete_account_while_being_owner_of_a_family_which")
        Response.redirect(conn, 303, "/settings/users", :alert, message)

      {:error, :actor} ->
        Fallback.call(conn, action: :destroy, context: context, status: 404)

      {:error, _} ->
        Fallback.call(conn, action: :destroy, context: context, status: 503)
    end
  end

  defp text(context, key) do
    {:ok, message} = I18n.t(context.locale, "controllers.settings.users." <> key)
    message
  end
end
