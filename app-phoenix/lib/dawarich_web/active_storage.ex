defmodule DawarichWeb.ActiveStorage do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.{RailsMessages, RubyInteger, Storage}
  alias Dawarich.Storage.Blobs
  alias DawarichWeb.{ActiveStorageUrls, RequestURL}
  alias DawarichWeb.ActiveStorage.FileServer
  alias DawarichWeb.Api.Params

  @reasons %{400 => "Bad Request", 404 => "Not Found", 422 => "Unprocessable Content"}
  @browser_accept ~r/,\s*\*\/\*|\*\/\*\s*,/

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    storage = Keyword.get_lazy(opts, :storage, fn -> Storage.services!(System.get_env()) end)
    action(Keyword.fetch!(opts, :action), fetch_query_params(conn), storage, now, opts)
  end

  defp action(:redirect, conn, storage, now, _opts) do
    with {:ok, id} <- RailsMessages.verified_blob_id(conn.path_params["signed_id"], now) do
      case Blobs.find(id) do
        nil ->
          page(conn, 404)

        blob ->
          disposition = conn.query_params["disposition"]

          service = Storage.service!(storage, blob.service_name)

          url =
            ActiveStorageUrls.service_url(service, blob, disposition, RequestURL.base(conn), now)

          conn
          |> put_resp_header("content-type", "text/html; charset=utf-8")
          |> put_resp_header("cache-control", "max-age=300, private")
          |> put_resp_header("location", url)
          |> send_resp(302, "")
      end
    else
      :error -> head(conn, 404)
    end
  end

  defp action(:disk, conn, storage, now, _opts) do
    with {:ok, %{"key" => key} = data} <-
           RailsMessages.verify_storage(conn.path_params["encoded_key"], "blob_key", now),
         %{service: "local", root: root} <- Storage.disk_service(storage, data["service_name"]),
         {:ok, path} <- Storage.safe_disk_path(root, key),
         {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} <-
           File.stat(path, time: :posix) do
      if is_nil(data["content_type"]) do
        DawarichWeb.ActiveStorage.Proxy.page(conn, 500)
      else
        conn
        |> put_resp_header("content-type", data["content_type"])
        |> put_resp_header("content-disposition", data["disposition"] || "attachment")
        |> FileServer.serve(
          path,
          size,
          mtime |> DateTime.from_unix!() |> DateTime.to_naive() |> Params.http_date()
        )
      end
    else
      _ -> head(conn, 404)
    end
  end

  defp action(:disk_update, conn, storage, now, _opts) do
    with {:ok, %{} = data} <-
           RailsMessages.verify_storage(conn.path_params["encoded_token"], "blob_token", now),
         %{service: "local"} = service <- Storage.disk_service(storage, data["service_name"]) do
      if acceptable?(conn, data), do: upload(conn, service, data), else: head(conn, 422)
    else
      _ -> head(conn, 404)
    end
  end

  defp action(:direct_upload, conn, storage, now, opts),
    do: DawarichWeb.ActiveStorage.UploadClosure.call(conn, storage, now, opts)

  defp acceptable?(conn, data) do
    media =
      case get_req_header(conn, "content-type") do
        [type | _] ->
          type |> String.split([";", ","]) |> hd() |> String.trim() |> String.downcase()

        [] ->
          nil
      end

    length =
      case get_req_header(conn, "content-length") do
        [value] -> RubyInteger.to_i(value)
        _ -> nil
      end

    data["content_type"] == media and data["content_length"] == length
  end

  defp upload(conn, service, %{"key" => key, "checksum" => checksum}) do
    with {:ok, path} <- Storage.safe_disk_path(service.root, key) do
      dir = Storage.tmp_dir!(service, "upload-" <> Storage.generate_key())
      tmp = Path.join(dir, "object")

      try do
        case File.open!(tmp, [:write, :binary], &copy(conn, &1)) do
          {:ok, conn} ->
            {digest, _size} = Storage.digest_file!(tmp)

            if is_nil(checksum) or digest == checksum do
              File.mkdir_p!(Path.dirname(path))
              File.rename!(tmp, path)
              head(conn, 204)
            else
              head(conn, 422)
            end

          {:error, conn} ->
            head(conn, 422)
        end
      after
        File.rm_rf(dir)
      end
    else
      :error -> head(conn, 422)
    end
  end

  defp copy(conn, io) do
    case read_body(conn, length: 1_048_576, read_length: 1_048_576) do
      {:ok, chunk, conn} -> IO.binwrite(io, chunk) && {:ok, conn}
      {:more, chunk, conn} -> IO.binwrite(io, chunk) && copy(conn, io)
      {:error, _reason} -> {:error, conn}
    end
  end

  defp head(conn, 204), do: conn |> no_cache() |> send_resp(204, "")

  defp head(conn, status) do
    type = if json?(conn), do: "application/json", else: "text/html"
    conn |> put_resp_header("content-type", type) |> no_cache() |> send_resp(status, "")
  end

  defp page(conn, status) do
    {type, body} =
      if json?(conn),
        do: {"application/json", ~s({"status":#{status},"error":"#{@reasons[status]}"})},
        else: {"text/html", File.read!(Dawarich.RailsRoot.join("public/#{status}.html"))}

    conn
    |> put_resp_header("content-type", type <> "; charset=UTF-8")
    |> delete_resp_header("cache-control")
    |> send_resp(status, body)
  end

  defp no_cache(conn), do: put_resp_header(conn, "cache-control", "no-cache")

  defp json?(conn) do
    case conn.path_params["filename"]
         |> List.wrap()
         |> List.last()
         |> to_string()
         |> Path.extname() do
      "" -> accept(get_req_header(conn, "accept")) == "application/json"
      extension -> extension == ".json"
    end
  end

  defp accept([value]) do
    unless value =~ @browser_accept,
      do: value |> String.split([",", ";"]) |> hd() |> String.trim() |> String.downcase()
  end

  defp accept(_values), do: nil
end
