defmodule DawarichWeb.NativeUploadTarget do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Accounts.Scope
  alias DawarichWeb.{ActiveStorageUrls, RailsCsrf, RequestURL}

  def init(opts), do: opts

  def call(conn, action) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with %{id: _} = user <- conn.assigns[:current_user],
         true <- get_req_header(conn, "sec-fetch-site") in [[], ["same-origin"]],
         true <- get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]],
         true <-
           RailsCsrf.valid?(
             conn.assigns[:rails_session] || %{},
             List.first(get_req_header(conn, "x-csrf-token"))
           ),
         {:ok, %{"upload_ref" => ref} = attrs, conn} <- body(conn),
         true <- map_size(attrs) == 1 and is_binary(ref) and byte_size(ref) <= 64 do
      scope = Scope.for_user(user, conn.assigns[:locale] || "en")

      result =
        if action == :cancel,
          do: Dawarich.Uploads.cancel(scope, ref),
          else: Dawarich.Uploads.target(scope, ref, %{})

      respond(conn, result, action)
    else
      {:error, status, conn} -> send_resp(conn, status, "")
      nil -> send_resp(conn, 401, "")
      _ -> send_resp(conn, 403, "")
    end
  end

  defp body(conn) do
    case read_body(conn, length: 4096, read_length: 4096) do
      {:ok, raw, conn} when byte_size(raw) <= 4096 ->
        case Jason.decode(raw) do
          {:ok, %{} = attrs} -> {:ok, attrs, conn}
          _ -> {:error, 400, conn}
        end

      {:more, _, conn} ->
        {:error, 413, conn}

      {:ok, _, conn} ->
        {:error, 413, conn}

      _ ->
        {:error, 400, conn}
    end
  end

  defp respond(conn, {:ok, :cancelled}, :cancel), do: send_resp(conn, 204, "")

  defp respond(conn, {:ok, grant}, :target) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response(grant, RequestURL.base(conn))))
  rescue
    _ -> send_resp(conn, 503, "")
  end

  defp respond(conn, {:error, reason}, _) do
    status =
      case reason do
        :stale_session -> 401
        :not_found -> 404
        _ -> 409
      end

    send_resp(conn, status, "")
  end

  def response(grant, base) do
    {url, headers} =
      ActiveStorageUrls.direct_upload(grant.storage, grant.blob, base, grant.issued_at)

    %{url: url, headers: Map.new(headers)}
  end
end
