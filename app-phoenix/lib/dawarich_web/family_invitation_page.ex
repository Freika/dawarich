defmodule DawarichWeb.FamilyInvitationPage do
  @moduledoc false

  import Plug.Conn
  alias Dawarich.{Entitlements, FamilyPageAccess, Repo, UserTimeZone}

  alias DawarichWeb.{
    FamilyInvitationDocument,
    LayoutAssigns,
    RailsAuth,
    RailsSession,
    RequestURL
  }

  def init(action), do: action

  def native?(conn, params),
    do:
      DawarichWeb.FamilyGate.session_supported?(conn) and
        read(params["token"], RailsAuth.call(conn, []).assigns.current_user) != :rails

  def read(token, user, opts \\ []) do
    if user, do: FamilyPageAccess.validate_settings!(Dawarich.UserSettings.get(user))
    now = Keyword.get(opts, :now, DateTime.utc_now())
    self_hosted = Keyword.get_lazy(opts, :self_hosted, &LayoutAssigns.self_hosted?/0)

    case Repo.query!(
           """
           SELECT i.token, i.email, i.status, i.expires_at, f.name, f.access_until,
                  o.plan, o.active_until, b.email
           FROM family_invitations i JOIN families f ON f.id = i.family_id
           LEFT JOIN users o ON o.id = f.creator_id AND o.deleted_at IS NULL
           JOIN users b ON b.id = i.invited_by_id AND b.deleted_at IS NULL
           WHERE i.token = $1
           """,
           [token]
         ).rows do
      [] ->
        {:error, 404}

      [[token, email, status, expires, name, access_until, plan, active_until, invited_by]] ->
        settings = if user, do: Dawarich.UserSettings.get(user), else: %{}
        date = UserTimeZone.local(settings, expires).local |> NaiveDateTime.to_date()

        cond do
          NaiveDateTime.compare(expires, DateTime.to_naive(now)) == :lt ->
            {:redirect, "this_invitation_has_expired"}

          status != 0 ->
            {:redirect, "this_invitation_is_no_longer_valid"}

          true ->
            {:ok,
             %{
               token: token,
               email: email,
               family_name: name,
               invited_by: invited_by,
               expires_date: date,
               plan_active?:
                 self_hosted or Entitlements.inherited?(access_until, plan, active_until, now)
             }}
        end
    end
  rescue
    ArgumentError -> :rails
  end

  def call(conn, :new), do: conn |> send_resp(404, "") |> halt()

  def call(conn, :show) do
    respond(
      conn,
      read(conn.path_params["token"], conn.assigns.current_user, now: conn.assigns.now)
    )
  end

  def respond(conn, result) do
    case result do
      {:ok, invitation} ->
        render(conn, invitation)

      {:redirect, message} ->
        alert =
          DawarichWeb.Translate.t(
            conn.assigns.locale,
            "controllers.family.invitations." <> message,
            %{}
          )

        conn
        |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"alert" => alert}}})
        |> put_resp_header("location", RequestURL.base(conn) <> "/")
        |> put_resp_content_type("text/html")
        |> send_resp(302, "")
        |> halt()

      {:error, 404} ->
        raise DawarichWeb.NotFoundError

      :rails ->
        conn
        |> DawarichWeb.RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream))
        |> halt()
    end
  end

  defp render(conn, invitation) do
    navbar =
      if conn.assigns.current_user,
        do:
          Dawarich.Navbar.load(conn.assigns.current_user,
            now: conn.assigns.now,
            self_hosted: conn.assigns.self_hosted
          )

    assigns =
      Map.merge(conn.assigns, %{
        invitation: invitation,
        page_title: nil,
        rails_js: true,
        rails_charts: false,
        flash: %{},
        navbar: navbar
      })

    content = FamilyInvitationDocument.document(assigns)

    html =
      DawarichWeb.PageEnvelope.document(conn, assigns, content) |> Phoenix.HTML.Safe.to_iodata()

    conn |> put_resp_content_type("text/html") |> send_resp(200, html) |> halt()
  end
end
