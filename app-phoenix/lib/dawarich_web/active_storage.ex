defmodule DawarichWeb.ActiveStorage do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.{RailsMessages, RubyInteger, Storage}
  alias Dawarich.Storage.Blobs
  alias DawarichWeb.{ActiveStorageUrls, RailsCsrf, RequestURL}
  alias DawarichWeb.ActiveStorage.FileServer
  alias DawarichWeb.Api.{Params, Respond}

  @reasons %{400 => "Bad Request", 404 => "Not Found", 422 => "Unprocessable Content"}
  @fields ~w(filename byte_size checksum content_type metadata)
  @browser_accept ~r/,\s*\*\/\*|\*\/\*\s*,/

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    storage = Keyword.get_lazy(opts, :storage, fn -> Storage.config!(System.get_env()) end)
    action(Keyword.fetch!(opts, :action), fetch_query_params(conn), storage, now, opts)
  end

  defp action(:redirect, conn, storage, now, _opts) do
    with {:ok, id} <- RailsMessages.verified_blob_id(conn.path_params["signed_id"], now) do
      case Blobs.find(id) do
        nil ->
          page(conn, 404)

        blob ->
          disposition = conn.query_params["disposition"]

          url =
            ActiveStorageUrls.service_url(storage, blob, disposition, RequestURL.base(conn), now)

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
         %{service: "local", root: root} <- storage,
         {:ok, path} <- Storage.safe_disk_path(root, key),
         {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} <-
           File.stat(path, time: :posix) do
      conn
      |> put_resp_header("content-type", data["content_type"] || "application/octet-stream")
      |> put_resp_header("content-disposition", data["disposition"] || "attachment")
      |> FileServer.serve(
        path,
        size,
        mtime |> DateTime.from_unix!() |> DateTime.to_naive() |> Params.http_date()
      )
    else
      _ -> head(conn, 404)
    end
  end

  defp action(:disk_update, conn, storage, now, _opts) do
    with {:ok, %{} = data} <-
           RailsMessages.verify_storage(conn.path_params["encoded_token"], "blob_token", now),
         %{service: "local"} <- storage do
      if acceptable?(conn, data), do: upload(conn, storage, data), else: head(conn, 422)
    else
      _ -> head(conn, 404)
    end
  end

  defp action(:direct_upload, conn, storage, now, opts) do
    with {:ok, body, conn} <- read_body(conn, length: 1_000_000),
         {:ok, %{} = params} <- json_object(body),
         true <- csrf?(conn, params) || :csrf,
         {:ok, %{} = blob} <- Map.fetch(params, "blob"),
         {:ok, attrs} <- blob_attrs(blob) do
      case Blobs.create_before_direct_upload(storage, attrs, DateTime.to_naive(now), opts) do
        {:ok, row} ->
          target = ActiveStorageUrls.direct_upload(storage, row, RequestURL.base(conn), now)
          json = direct_upload_json(row, target)

          conn
          |> put_resp_content_type("application/json")
          |> Respond.rack_etag(json)
          |> send_resp(200, json)

        {:replay, reason} ->
          raise ArgumentError, reason
      end
    else
      :csrf -> page(conn, 422)
      {:error, :invalid} -> page(conn, 422)
      _ -> page(conn, 400)
    end
  end

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

  defp upload(conn, storage, %{"key" => key, "checksum" => checksum}) do
    with {:ok, path} <- Storage.safe_disk_path(storage.root, key) do
      dir = Storage.tmp_dir!(storage, "upload-" <> Storage.generate_key())
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

  defp json_object(""), do: {:ok, %{}}
  defp json_object(body), do: Jason.decode(body)

  defp csrf?(conn, params) do
    session = conn.assigns[:rails_session] || %{}
    tokens = [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")]

    origin? =
      case get_req_header(conn, "origin") do
        [] -> true
        [origin] -> origin == RequestURL.base(conn)
        _ -> false
      end

    origin? and Enum.any?(tokens, &(is_binary(&1) and RailsCsrf.valid?(session, &1)))
  end

  defp blob_attrs(blob) do
    checksum = blob["checksum"]

    cond do
      is_nil(checksum) or (is_binary(checksum) and String.trim(checksum) == "") ->
        {:error, :invalid}

      is_binary(blob["filename"]) and is_integer(blob["byte_size"]) and blob["byte_size"] >= 0 and
        is_binary(checksum) and (is_nil(blob["content_type"]) or is_binary(blob["content_type"])) and
          (is_nil(blob["metadata"]) or is_map(blob["metadata"])) ->
        {:ok, Map.take(blob, @fields)}

      true ->
        :error
    end
  end

  defp direct_upload_json(row, {url, headers}) do
    fields =
      Enum.map(row.pairs, fn
        {"metadata", value} ->
          {"metadata", Jason.decode!(value || "{}", objects: :ordered_objects)}

        {"created_at", _value} ->
          {"created_at", row.created_at_json}

        pair ->
          pair
      end)

    extra = [
      {"attachable_sgid", RailsMessages.attachable_sgid(row.id)},
      {"signed_id", RailsMessages.blob_id(row.id)},
      {"direct_upload", Jason.OrderedObject.new(url: url, headers: headers)}
    ]

    RailsMessages.json(Jason.OrderedObject.new(fields ++ extra))
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
