defmodule DawarichWeb.FamilyActions do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{Repo, FamilyPageAccess}
  alias Dawarich.Families.{WebCreate, WebUpdate, WebDestroy}

  alias DawarichWeb.{
    RailsAuth,
    RailsCsrf,
    RailsSession,
    LayoutAssigns,
    Locale,
    Translate,
    RequestURL
  }

  def init(action), do: action

  def prepare(%{private: %{family_prepared: true}} = conn), do: conn

  def prepare(conn) do
    conn =
      conn
      |> fetch_query_params()
      |> Plug.Parsers.call(
        Plug.Parsers.init(parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason)
      )
      |> RailsAuth.call([])
      |> LayoutAssigns.call([])
      |> Locale.call([])
      |> put_private(:family_prepared, true)

    method =
      if conn.method == "POST",
        do: String.upcase(conn.params["_method"] || "POST"),
        else: conn.method

    conn = %{conn | method: method}
    tokens = [conn.params["authenticity_token"] | get_req_header(conn, "x-csrf-token")]
    origins = get_req_header(conn, "origin")

    cond do
      is_nil(conn.assigns.current_user) ->
        redirect(conn, 302, "/users/sign_in", nil, nil)

      origins != [] and origins != [RequestURL.base(conn)] ->
        conn |> send_resp(422, "") |> halt()

      not Enum.any?(tokens, &RailsCsrf.valid?(conn.assigns.rails_session, &1)) ->
        conn |> send_resp(422, "") |> halt()

      true ->
        conn
    end
  rescue
    _error -> conn |> send_resp(500, "") |> halt()
  end

  def context(conn),
    do: %{
      now: conn.assigns.now,
      locale: conn.assigns.locale,
      self_hosted: conn.assigns.self_hosted
    }

  def call(conn, :destroy) do
    conn = prepare(conn)

    if conn.halted do
      conn
    else
      result = WebDestroy.run(Repo, conn.assigns.current_user, context(conn))

      case result do
        {:ok, _id} ->
          redirect_key(
            conn,
            302,
            "/family/new",
            "notice",
            "controllers.families.family_deleted_successfully"
          )

        {:refused, :members_present} ->
          redirect_key(
            conn,
            302,
            "/family",
            "alert",
            "controllers.families.cannot_delete_family_with_members_remove_all_members_first"
          )

        {:error, reason} ->
          error(conn, reason)
      end
    end
  rescue
    _error -> error(conn, :failed)
  end

  def call(conn, action) do
    conn = prepare(conn)

    if conn.halted do
      conn
    else
      ctx = context(conn)
      user = conn.assigns.current_user
      family = WebCreate.family(Repo, user.id)

      if not FamilyPageAccess.available?(user, family, ctx.self_hosted, ctx.now) do
        redirect_key(
          conn,
          303,
          "/family/new",
          "alert",
          "controllers.application.family_plan_required"
        )
      else
        attrs = conn.params["family"]

        result =
          if is_map(attrs) and map_size(attrs) > 0,
            do: change(action, user, attrs, ctx),
            else: {:error, :missing_parameter}

        respond(conn, action, result)
      end
    end
  rescue
    _error -> conn |> send_resp(500, "") |> halt()
  end

  defp change(:create, user, attrs, ctx), do: WebCreate.run(Repo, user, attrs, ctx)
  defp change(:update, user, attrs, ctx), do: WebUpdate.run(Repo, user, attrs, ctx)

  defp respond(conn, action, {:ok, _id}) do
    key =
      if action == :create, do: "family_created_successfully", else: "family_updated_successfully"

    redirect_key(conn, 302, "/family", "notice", "controllers.families." <> key)
  end

  defp respond(conn, action, {:invalid, errors, name}), do: invalid(conn, action, errors, name)
  defp respond(conn, _action, {:error, reason}), do: error(conn, reason)

  def error(conn, :not_in_family),
    do:
      redirect_key(
        conn,
        302,
        "/family/new",
        "alert",
        "controllers.families.you_are_not_in_a_family"
      )

  def error(conn, :not_authorized),
    do: DawarichWeb.FamilyGate.redirect(conn, "/", :not_authorized)

  def error(conn, :not_found), do: conn |> send_resp(404, "") |> halt()
  def error(conn, :missing_parameter), do: conn |> send_resp(400, "") |> halt()
  def error(conn, _reason), do: conn |> send_resp(500, "") |> halt()

  def redirect_key(conn, status, path, kind, key, locale \\ nil, bindings \\ %{}) do
    message = Translate.t(locale || conn.assigns.locale, key, bindings)
    redirect(conn, status, path, kind, message)
  end

  def redirect(conn, status, path, kind, message) do
    conn =
      if kind,
        do:
          RailsSession.stage(conn, %{
            "flash" => %{"discard" => [], "flashes" => %{kind => message}}
          }),
        else: conn

    conn
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_content_type("text/html")
    |> send_resp(status, "")
    |> halt()
  end

  defp invalid(conn, action, errors, name) do
    user = conn.assigns.current_user
    state = if action == :create, do: :new, else: :edit

    {:ok, page} =
      Dawarich.FamilyPage.read(user, state,
        now: conn.assigns.now,
        self_hosted: conn.assigns.self_hosted
      )

    page = Map.merge(page, %{name: name, errors: errors})
    page = if action == :update, do: put_in(page.family.name, name), else: page

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        page: page,
        upgrade_href: nil,
        flash:
          if(action == :create,
            do: %{
              "alert" =>
                Translate.t(
                  conn.assigns.locale,
                  "controllers.families.failed_to_create_family",
                  %{}
                )
            },
            else: %{}
          ),
        rails_js: true,
        rails_charts: false,
        navbar:
          Dawarich.Navbar.load(user, now: conn.assigns.now, self_hosted: conn.assigns.self_hosted),
        page_title:
          Translate.t(
            conn.assigns.locale,
            if(action == :create,
              do: "families.new.new_family",
              else: "families.edit.editing_family"
            ),
            %{}
          )
      })

    content =
      if action == :create,
        do: DawarichWeb.FamilyForms.new_family(assigns),
        else: DawarichWeb.FamilyForms.edit_family(assigns)

    app = DawarichWeb.Layouts.app(Map.put(assigns, :inner_content, content))

    html =
      DawarichWeb.Layouts.root(Map.put(assigns, :inner_content, app))
      |> Phoenix.HTML.Safe.to_iodata()

    conn |> put_resp_content_type("text/html") |> send_resp(422, html) |> halt()
  end
end
