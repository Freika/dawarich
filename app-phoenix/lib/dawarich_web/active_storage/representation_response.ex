defmodule DawarichWeb.ActiveStorage.RepresentationResponse do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Storage
  alias Dawarich.Storage.Representations
  alias DawarichWeb.{ActiveStorageUrls, RequestURL}
  alias DawarichWeb.ActiveStorage.Proxy

  def call(conn, blob, variation, storage, now, opts) do
    conn = fetch_query_params(conn)
    case Representations.processed(blob, variation, storage, now, opts) do
      {:ok, image} ->
        service = Storage.service!(storage, image.service_name)
        if Keyword.get(opts, :action, mode(conn)) == :proxy do
          Proxy.serve(conn, image, service, Keyword.put(opts, :representation, true))
        else
          url = ActiveStorageUrls.service_url(service, image, conn.query_params["disposition"], RequestURL.base(conn), now)
          conn |> put_resp_header("content-type", "text/html; charset=utf-8") |> put_resp_header("content-length", "0") |> put_resp_header("cache-control", "max-age=300, private") |> put_resp_header("location", url) |> send_resp(302, "")
        end
      {:error, _} -> Proxy.page(conn, 500)
    end
  end

  defp mode(conn), do: if(Enum.at(conn.path_info, 3) == "proxy", do: :proxy, else: :redirect)
end
