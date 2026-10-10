defmodule DawarichWeb.AdminWritesGate do
  @moduledoc false
  alias Dawarich.Auth.Admission
  alias DawarichWeb.{AdminGate, RailsAuth, Strangler}

  @markers ~w(client aff via referral invitation_token pending_import_ticket dawarich_client)

  def background?(conn, _params),
    do: Dawarich.Standalone.enabled?() or eligible?(conn, :background)

  def context(opts) do
    Keyword.get(opts, :context, %{})
    |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED") == "true")
    |> Map.put_new_lazy(:oidc, &Admission.oidc?/0)
  end

  def eligible?(conn, action, opts \\ []) do
    context = context(opts)
    conn = RailsAuth.call(conn, auth_options(context))
    session = conn.assigns.rails_session
    actor = conn.assigns.current_user

    route?(conn, action) and Strangler.page_request?(conn) and
      Admission.context(session, conn, context.oidc, context.self_hosted or conn.method == "POST") ==
        :ok and
      session_identity?(session, actor) and AdminGate.supported?(actor) and
      not Enum.any?(@markers, &Map.has_key?(session, &1)) and
      Enum.all?(
        ~w(turbo-frame x-http-method-override x-dawarich-client),
        &(Plug.Conn.get_req_header(conn, &1) == [])
      )
  rescue
    _ -> false
  end

  def auth_options(context),
    do: if(context[:secret], do: [secret: context.secret], else: [])

  defp session_identity?(%{"warden.user.user.key" => [[id], salt]}, %{id: id})
       when is_integer(id) and is_binary(salt),
       do: true

  defp session_identity?(_, _), do: false

  defp route?(%{method: method, request_path: "/settings/background_jobs"}, :background),
    do: method in ~w(POST PATCH)

  defp route?(_, _), do: false
end
