defmodule DawarichWeb.AdminWritesGate do
  @moduledoc false
  alias Dawarich.Auth.Admission
  alias DawarichWeb.{AdminGate, RailsAuth, Strangler}

  @markers ~w(client aff via referral invitation_token pending_import_ticket dawarich_client)
  @member ~r/\A\/settings\/users\/[1-9][0-9]{0,17}\z/
  @security ~r/\A\/settings\/users\/[1-9][0-9]{0,17}\/(regenerate_api_key|send_password_reset)\z/

  def create?(conn, _params), do: owned?(conn, :create)
  def update?(conn, _params), do: owned?(conn, :update)
  def registration?(conn, _params), do: owned?(conn, :registration)
  def instance?(conn, _params), do: owned?(conn, :instance)
  def background?(conn, _params), do: owned?(conn, :background)
  def rotate?(conn, _params), do: owned?(conn, :rotate)
  def reset?(conn, _params), do: owned?(conn, :reset)

  def destroy?(conn, _params), do: owned?(conn, :destroy)
  def test_geocoding?(conn, _params), do: owned?(conn, :test_geocoding)

  defp owned?(conn, action),
    do: Dawarich.Standalone.enabled?() or eligible?(conn, action)

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
      Admission.context(
        session,
        conn.req_headers,
        context.oidc,
        context.self_hosted or
          (action == :background and conn.method == "POST")
      ) == :ok and
      session_identity?(session, actor) and AdminGate.supported?(actor) and
      (action == :background or actor.admin == true) and
      not Enum.any?(@markers, &Map.has_key?(session, &1)) and
      Enum.all?(
        ~w(turbo-frame x-http-method-override x-dawarich-client),
        &(Plug.Conn.get_req_header(conn, &1) == [])
      ) and
      (action == :background or conn.query_string == "")
  rescue
    _ -> false
  end

  def auth_options(context),
    do: if(context[:secret], do: [secret: context.secret], else: [])

  defp session_identity?(%{"warden.user.user.key" => [[id], salt]}, %{id: id})
       when is_integer(id) and is_binary(salt),
       do: true

  defp session_identity?(_, _), do: false

  defp route?(%{method: method, request_path: path}, :destroy),
    do: method in ~w(POST DELETE) and Regex.match?(@member, path)

  defp route?(%{method: "POST", request_path: "/admin/settings/test_geocoding"}, :test_geocoding),
    do: true

  defp route?(%{method: "POST", request_path: "/settings/users"}, :create), do: true

  defp route?(%{method: method, request_path: path}, :update),
    do: method in ~w(POST PUT PATCH) and Regex.match?(@member, path)

  defp route?(
         %{method: method, request_path: "/settings/users/update_registration_settings"},
         :registration
       ),
       do: method in ~w(POST PATCH)

  defp route?(%{method: method, request_path: "/admin/settings"}, :instance),
    do: method in ~w(POST PUT PATCH)

  defp route?(%{method: method, request_path: "/settings/background_jobs"}, :background),
    do: method in ~w(POST PATCH)

  defp route?(%{method: "POST", request_path: path}, action) when action in [:rotate, :reset] do
    suffix = if action == :rotate, do: "/regenerate_api_key", else: "/send_password_reset"
    Regex.match?(@security, path) and String.ends_with?(path, suffix)
  end

  defp route?(_, _), do: false
end
