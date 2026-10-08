defmodule DawarichWeb.TestEmailGate do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  alias Dawarich.Auth.Admission
  alias Dawarich.Mail.TestEmail
  alias DawarichWeb.RailsAuth

  @path "/settings/general/test_email"
  @markers ~w(client aff via referral invitation_token pending_import_ticket dawarich_client)
  @accepts [
    "text/html",
    "text/vnd.turbo-stream.html",
    "text/vnd.turbo-stream.html, text/html",
    "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
  ]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if non_admin?(conn),
      do:
        conn
        |> put_resp_header("x-dawarich-mail-owner", "native-test-email")
        |> send_resp(403, "")
        |> halt(),
      else: conn
  end

  def owned?(conn, _params), do: Dawarich.Standalone.enabled?() or eligible?(conn)

  def context(opts) do
    Keyword.get(opts, :context, %{})
    |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED") == "true")
    |> Map.put_new_lazy(:oidc, &Admission.oidc?/0)
    |> Map.put_new_lazy(:env, &System.get_env/0)
  end

  def eligible?(conn, opts \\ []) do
    context = context(opts)
    conn = RailsAuth.call(conn, [])
    actor = conn.assigns.current_user
    session = conn.assigns.rails_session

    conn.method == "POST" and conn.request_path == @path and conn.query_string == "" and
      format(conn) != nil and
      Admission.context(session, conn.req_headers, context.oidc, context.self_hosted) == :ok and
      identity?(session, actor) and actor.admin == true and
      is_map(Dawarich.UserSettings.get(actor)) and
      not Enum.any?(@markers, &Map.has_key?(session, &1)) and
      Enum.all?(~w(turbo-frame x-requested-with), &(Plug.Conn.get_req_header(conn, &1) == [])) and
      TestEmail.supported?(context.env)
  rescue
    _ -> false
  end

  def non_admin?(%{method: "POST", request_path: @path} = conn) do
    conn = RailsAuth.call(conn, [])

    case conn.assigns.current_user do
      %{} = actor -> Map.get(actor, :admin) != true
      _ -> false
    end
  end

  def non_admin?(_conn), do: false

  def format(conn) do
    case Plug.Conn.get_req_header(conn, "accept") do
      [] ->
        :html

      [accept] when accept in @accepts ->
        if String.starts_with?(accept, "text/vnd.turbo-stream.html"), do: :turbo, else: :html

      [accept] ->
        case DawarichWeb.PageAccept.formats(accept, false) do
          ["text/html" | _] -> :html
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp identity?(%{"warden.user.user.key" => [[id], salt]}, %{id: id})
       when is_integer(id) and is_binary(salt),
       do: true

  defp identity?(_, _), do: false
end
