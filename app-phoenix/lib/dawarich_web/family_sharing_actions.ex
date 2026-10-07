defmodule DawarichWeb.FamilySharingActions do
  @moduledoc false
  use Phoenix.Component
  import Plug.Conn
  alias Dawarich.{Accounts, FamilyPage, Families.SharingUpdate}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.FamilyActions
  def init(action), do: action

  def call(conn, _action) do
    conn = FamilyActions.prepare(conn)

    if conn.halted do
      conn
    else
      user =
        conn.assigns.current_user
        |> Map.put(:timezone, Dawarich.UserSettings.get(conn.assigns.current_user)["timezone"])
        |> Map.put(:locale, conn.assigns.locale)

      result =
        SharingUpdate.web_call(
          user,
          Map.drop(conn.params, ["history_before_sharing"]),
          conn.assigns.now
        )

      respond(conn, result)
    end
  rescue
    _error ->
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(500, Ruby.json({:object, [{"success", false}]}))
      |> halt()
  end

  def respond(conn, {:ok, status, {:object, fields} = body}) do
    accept = Enum.join(get_req_header(conn, "accept"), ",")

    cond do
      String.ends_with?(conn.request_path, ".json") or
          String.contains?(accept, "application/json") ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, Ruby.json(body))
        |> halt()

      String.contains?(accept, "text/vnd.turbo-stream.html") ->
        stream(conn, status, Map.new(fields))

      true ->
        conn |> send_resp(406, "") |> halt()
    end
  end

  def respond(conn, _result), do: FamilyActions.error(conn, :failed)

  defp stream(conn, 404, fields) do
    assigns =
      Map.merge(conn.assigns, %{__changed__: nil, message: fields["error"], kind: "error"})

    body = flash_stream(assigns) |> Phoenix.HTML.Safe.to_iodata()
    conn |> put_resp_content_type("text/vnd.turbo-stream.html") |> send_resp(404, body) |> halt()
  end

  defp stream(conn, status, fields) do
    user = Accounts.get(conn.assigns.current_user.id)
    {:ok, page} = FamilyPage.read(user, :show, now: conn.assigns.now, self_hosted: true)

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        page: page,
        message: fields["message"],
        kind: if(status == 200, do: "success", else: "error")
      })

    body = streams(assigns) |> Phoenix.HTML.Safe.to_iodata()
    conn |> put_resp_content_type("text/vnd.turbo-stream.html") |> send_resp(200, body) |> halt()
  end

  defp flash_stream(assigns) do
    ~H"""
    <turbo-stream action="append" target="flash-messages">
      <template>
        <DawarichWeb.Chrome.flash_message type={@kind} message={@message} locale={@locale} />
      </template>
    </turbo-stream>
    """
  end

  defp streams(assigns) do
    ~H"""
    <turbo-stream action="replace" target={"location-sharing-#{@page.me.id}"}>
      <template>
        <DawarichWeb.FamilyControls.sharing_toggle
          member={@page.me}
          locale={@locale}
          now={@now}
          rails_csrf_token={@rails_csrf_token}
        />
      </template>
    </turbo-stream>
    <turbo-stream action="replace" target="family-navbar-indicator">
      <template>
        <DawarichWeb.NavbarParts.family_indicator
          locale={@locale}
          sharing={@page.me.sharing.enabled?}
        />
      </template>
    </turbo-stream>
    <turbo-stream action="replace" target="family-getting-started-slot">
      <template>
        <DawarichWeb.FamilyGettingStarted.getting_started
          page={@page}
          locale={@locale}
          rails_csrf_token={@rails_csrf_token}
          self_hosted={@self_hosted}
        />
      </template>
    </turbo-stream>
    <turbo-stream action="append" target="flash-messages">
      <template>
        <DawarichWeb.Chrome.flash_message type={@kind} message={@message} locale={@locale} />
      </template>
    </turbo-stream>
    """
  end
end
