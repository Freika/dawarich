defmodule DawarichWeb.WelcomeGate do
  @moduledoc false
  alias Dawarich.Auth.Admission
  alias Dawarich.{RailsSecret, Trial.Welcome}
  alias DawarichWeb.Strangler

  def context(opts) do
    context = Keyword.get(opts, :context, %{}) |> Map.put_new_lazy(:env, &System.get_env/0)

    context
    |> Map.put_new_lazy(:secret, &RailsSecret.fetch/0)
    |> Map.put_new(:jwt_secret, context.env["JWT_SECRET_KEY"])
    |> Map.put_new_lazy(:oidc, fn -> Admission.oidc?(context.env) end)
  end

  def owned?(conn, _params, opts \\ []) do
    context = context(opts)

    envelope?(conn) and
      match?({:ok, _}, Welcome.prepare(conn, URI.decode_query(conn.query_string), context))
  rescue
    _ -> false
  end

  def envelope?(conn) do
    pairs = conn.query_string |> URI.query_decoder() |> Enum.to_list()

    allowed =
      if Dawarich.Standalone.enabled?(),
        do: ~w(token locale client aff via referral),
        else: ["token"]

    (Dawarich.Standalone.enabled?() or Plug.Conn.get_req_header(conn, "x-dawarich-client") == []) and
      conn.request_path == "/trial/welcome" and conn.method in ["GET", "HEAD"] and
      Strangler.page_request?(conn) and Admission.headers(conn.req_headers) == :ok and
      byte_size(conn.query_string) <= 65_536 and length(pairs) <= length(allowed) and
      length(pairs) == length(Enum.uniq_by(pairs, &elem(&1, 0))) and
      Enum.all?(pairs, fn {key, value} -> key in allowed and String.valid?(value) end) and
      not Regex.match?(~r/%(?![0-9a-fA-F]{2})/, conn.query_string) and
      Enum.all?(
        ~w(turbo-frame x-http-method-override x-forwarded-for client-ip forwarded transfer-encoding),
        &(Plug.Conn.get_req_header(conn, &1) == [])
      ) and
      Plug.Conn.get_req_header(conn, "content-length") in [[], ["0"]]
  rescue
    _ -> false
  end
end
