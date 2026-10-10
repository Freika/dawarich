defmodule DawarichWeb.FamilyInvitationAcceptance do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Accounts.Scope

  alias DawarichWeb.{
    LayoutAssigns,
    Locale,
    RailsAuth,
    RailsCsrf,
    RailsSession,
    RequestURL,
    RequireUser,
    Translate
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case envelope(conn) do
      {:error, status} ->
        refuse(conn, status)

      :ok ->
        conn = prepare(conn)

        if conn.halted do
          conn
        else
          scope = Scope.for_user(conn.assigns.current_user, conn.assigns.locale)

          Dawarich.Families.accept_invitation(scope, conn.params["token"],
            now: conn.assigns.now,
            self_hosted: conn.assigns.self_hosted
          )
          |> respond(conn)
        end
    end
  rescue
    Plug.Parsers.RequestTooLargeError -> refuse(conn, 413)
    Plug.Conn.InvalidQueryError -> refuse(conn, 400)
    Plug.Parsers.ParseError -> refuse(conn, 400)
    _ -> refuse(conn, 500)
  end

  defp envelope(conn) do
    type = get_req_header(conn, "content-type") |> List.first("") |> String.split(";") |> hd()

    cond do
      get_req_header(conn, "x-http-method-override") != [] -> {:error, 400}
      Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, conn.query_string) -> {:error, 400}
      type not in ["application/x-www-form-urlencoded", "application/json"] -> {:error, 415}
      true -> :ok
    end
  end

  defp prepare(conn) do
    conn =
      conn
      |> fetch_query_params()
      |> Plug.Parsers.call(
        Plug.Parsers.init(
          parsers: [:urlencoded, :json],
          pass: [],
          json_decoder: Jason,
          length: 131_072,
          read_length: 131_072,
          body_reader: {__MODULE__, :read_body, []}
        )
      )
      |> RailsAuth.call([])
      |> LayoutAssigns.call([])
      |> Locale.call([])

    origins = get_req_header(conn, "origin")
    tokens = [conn.params["authenticity_token"] | get_req_header(conn, "x-csrf-token")]

    cond do
      conn.params["_method"] not in [nil, "post", "POST"] ->
        refuse(conn, 400)

      conn.assigns.current_user == nil ->
        RequireUser.call(conn, [])

      origins != [] and origins != [RequestURL.base(conn)] ->
        refuse(conn, 422)

      not Enum.any?(
        tokens,
        &RailsCsrf.valid?(conn.assigns.rails_session, &1, conn.request_path, "POST")
      ) ->
        refuse(conn, 422)

      true ->
        conn
    end
  end

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, raw, conn} = result ->
        if Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, raw) and
             DawarichWeb.Api.Body.kind(conn) == :form,
           do: raise(Plug.Conn.InvalidQueryError),
           else: result

      result ->
        result
    end
  end

  defp respond({:ok, _}, conn),
    do:
      redirect_key(
        conn,
        "/family",
        "controllers.family.memberships.welcome_to_the_family",
        "notice"
      )

  defp respond({:error, reason}, conn) do
    key =
      case reason do
        :invitation_expired ->
          "controllers.family.memberships.invitation_expired"

        :invitation_processed ->
          "controllers.family.memberships.invitation_processed"

        :invitation_email_mismatch ->
          "controllers.family.memberships.invitation_email_mismatch"

        :already_in_family ->
          "services.families.accept_invitation.you_must_leave_your_current_family_before_joining_a_new"

        :family_lapsed ->
          "services.families.accept_invitation.this_family_s_plan_is_no_longer_active"

        :family_full ->
          "services.families.accept_invitation.this_family_has_reached_the_maximum_number_of_members"

        _ ->
          "controllers.family.memberships.an_unexpected_error_occurred_please_try_again_later"
      end

    redirect_key(conn, "/", key, "alert")
  end

  defp redirect_key(conn, path, key, kind),
    do: redirect(conn, path, {kind, Translate.t(conn.assigns.locale, key, %{})})

  defp redirect(conn, path, flash) do
    conn =
      if flash do
        {kind, text} = flash
        RailsSession.stage(conn, %{"flash" => %{"discard" => [], "flashes" => %{kind => text}}})
      else
        conn
      end

    conn
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end

  defp refuse(conn, status), do: conn |> send_resp(status, "") |> halt()
end
