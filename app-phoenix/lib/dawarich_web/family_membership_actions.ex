defmodule DawarichWeb.FamilyMembershipActions do
  @moduledoc false
  alias Dawarich.Repo
  alias Dawarich.Families.WebMemberships
  alias DawarichWeb.FamilyActions
  def init(action), do: action

  def call(conn, :destroy) do
    conn = FamilyActions.prepare(conn)

    if conn.halted do
      conn
    else
      id = String.to_integer(conn.path_params["id"])

      result =
        WebMemberships.run(Repo, conn.assigns.current_user, id, FamilyActions.context(conn))

      case result do
        {:ok, %{self?: true}} ->
          FamilyActions.redirect_key(
            conn,
            302,
            "/family/new",
            "notice",
            "controllers.family.memberships.you_have_left_the_family"
          )

        {:ok, %{email: email}} ->
          FamilyActions.redirect_key(
            conn,
            302,
            "/family",
            "notice",
            "controllers.family.memberships.email_has_been_removed_from_the_family",
            nil,
            %{"email" => email}
          )

        {:refused, key} ->
          FamilyActions.redirect_key(
            conn,
            302,
            "/family",
            "alert",
            "services.families.memberships.destroy." <> key
          )

        {:error, reason} ->
          FamilyActions.error(conn, reason)
      end
    end
  rescue
    _error -> FamilyActions.error(conn, :failed)
  end
end
