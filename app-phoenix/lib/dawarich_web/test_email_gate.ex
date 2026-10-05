defmodule DawarichWeb.TestEmailGate do
  @moduledoc false

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

  def owned?(conn, _params), do: eligible?(conn)

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
      identity?(session, actor) and is_map(actor.settings) and
      not Enum.any?(@markers, &Map.has_key?(session, &1)) and
      Enum.all?(~w(turbo-frame x-requested-with), &(Plug.Conn.get_req_header(conn, &1) == [])) and
      TestEmail.supported?(context.env)
  rescue
    _ -> false
  end

  def format(conn) do
    case Plug.Conn.get_req_header(conn, "accept") do
      [] ->
        :html

      [accept] when accept in @accepts ->
        if String.starts_with?(accept, "text/vnd.turbo-stream.html"), do: :turbo, else: :html

      _ ->
        nil
    end
  end

  defp identity?(%{"warden.user.user.key" => [[id], salt]}, %{id: id})
       when is_integer(id) and is_binary(salt),
       do: true

  defp identity?(_, _), do: false
end
