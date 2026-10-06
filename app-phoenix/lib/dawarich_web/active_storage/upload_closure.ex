defmodule DawarichWeb.ActiveStorage.UploadClosure do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{RailsMessages, RubyInteger, Storage}
  alias Dawarich.Storage.Blobs
  alias DawarichWeb.{ActiveStorageUrls, RailsCsrf, RequestURL}
  alias DawarichWeb.Api.Respond

  @fields ~w(filename byte_size checksum content_type metadata)
  @reasons %{400 => "Bad Request", 422 => "Unprocessable Content", 500 => "Internal Server Error"}

  def call(conn, storage, now, opts) do
    with {:ok, params, conn} <- params(conn),
         true <- csrf?(conn, params) || :csrf,
         {:ok, attrs} <- attrs(params["blob"]) do
      service = Storage.service!(storage, storage.default)
      {:ok, row} = Blobs.create_before_direct_upload(service, attrs, DateTime.to_naive(now), opts)
      target = ActiveStorageUrls.direct_upload(service, row, RequestURL.base(conn), now)
      json = direct_upload_json(row, target)
      conn |> put_resp_content_type("application/json") |> put_resp_header("content-length", to_string(byte_size(json))) |> Respond.rack_etag(json) |> send_resp(200, json)
    else
      :csrf -> page(conn, 422)
      {:error, :invalid} -> page(conn, 422)
      _ -> page(conn, 400)
    end
  end

  defp params(%{body_params: %{} = params} = conn) when not is_struct(params), do: {:ok, params, conn}
  defp params(conn) do
    type = get_req_header(conn, "content-type") |> List.first("") |> String.split(";") |> hd() |> String.downcase()
    if type == "multipart/form-data" do
      opts = Plug.Parsers.init(parsers: [:multipart], pass: ["*/*"], length: 9_223_372_036_854_775_807)
      conn = Plug.Parsers.call(conn, opts)
      {:ok, conn.body_params, conn}
    else
      with {:ok, body, conn} <- raw(conn, []), {:ok, params} <- decode(type, body), true <- is_map(params) do
        {:ok, Map.merge(conn.query_params, params), conn}
      else
        _ -> :error
      end
    end
  rescue
    _ -> :error
  end

  defp raw(%{private: %{dawarich_raw_body: body}} = conn, []), do: {:ok, body, conn}
  defp raw(conn, acc) do
    case read_body(conn, length: 65_536, read_length: 65_536) do
      {:ok, bytes, conn} -> {:ok, IO.iodata_to_binary(Enum.reverse([bytes | acc])), conn}
      {:more, bytes, conn} -> raw(conn, [bytes | acc])
      _ -> :error
    end
  end

  defp decode(_type, ""), do: {:ok, %{}}
  defp decode(type, body) when type in ~w(application/json text/x-json application/jsonrequest), do: Jason.decode(body)
  defp decode("application/x-www-form-urlencoded", body), do: {:ok, Plug.Conn.Query.decode(body)}
  defp decode(_type, _body), do: {:ok, %{}}

  defp csrf?(conn, params) do
    session = conn.assigns[:rails_session] || %{}
    origin = get_req_header(conn, "origin")
    tokens = [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")]
    origin in [[], [RequestURL.base(conn)]] and Enum.any?(tokens, &(is_binary(&1) and RailsCsrf.valid?(session, &1)))
  end

  defp attrs(blob) when is_map(blob) and map_size(blob) > 0 do
    attrs = Map.take(blob, @fields)
    cond do
      map_size(attrs) == 0 -> :error
      blob["checksum"] in [nil, ""] -> {:error, :invalid}
      true ->
        size = case blob["byte_size"] do
          value when is_integer(value) -> value
          value when is_binary(value) -> RubyInteger.to_i(value)
          _ -> nil
        end
        metadata = if is_map(blob["metadata"]), do: blob["metadata"], else: nil
        {:ok, attrs |> Map.put("byte_size", size) |> Map.put("metadata", metadata)}
    end
  end
  defp attrs(_), do: :error

  defp direct_upload_json(row, {url, headers}) do
    fields = Enum.map(row.pairs, fn
      {"metadata", value} -> {"metadata", Jason.decode!(value || "{}", objects: :ordered_objects)}
      {"created_at", _} -> {"created_at", row.created_at_json}
      pair -> pair
    end)
    extra = [{"attachable_sgid", RailsMessages.attachable_sgid(row.id)}, {"signed_id", RailsMessages.blob_id(row.id)}, {"direct_upload", Jason.OrderedObject.new(url: url, headers: headers)}]
    RailsMessages.json(Jason.OrderedObject.new(fields ++ extra))
  end

  def page(conn, status) do
    json? = get_req_header(conn,"accept") == ["application/json"] or conn.path_params["format"] == "json"
    {type, body} = if json?, do: {"application/json", Jason.encode!(Jason.OrderedObject.new(status: status, error: @reasons[status]))}, else: {"text/html", File.read!(Dawarich.RailsRoot.join("public/#{status}.html"))}
    conn |> put_resp_header("content-type", type <> "; charset=UTF-8") |> put_resp_header("content-length", to_string(byte_size(body))) |> delete_resp_header("cache-control") |> send_resp(status, body)
  end
end
