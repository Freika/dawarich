defmodule Dawarich.Trips.Attachments do
  @moduledoc false
  alias Dawarich.{RailsMessages, Storage}
  alias Dawarich.Storage.{NativePurge, Representations, Variation}
  alias DawarichWeb.BlobPath

  def resolve(repo, sgid) do
    with {:ok, id} <- RailsMessages.verified_attachable_blob_id(sgid) do
      case repo.query!(
             "SELECT id,filename,content_type,metadata,byte_size FROM active_storage_blobs WHERE id=$1",
             [id],
             log: false
           ).rows do
        [[id, filename, type, metadata, size]] ->
          if NativePurge.pending?(metadata),
            do: :pending,
            else:
              {:ok,
               %{
                 id: id,
                 filename: filename,
                 content_type: type,
                 metadata: metadata,
                 byte_size: size
               }}

        [] ->
          :missing
      end
    else
      _ -> :invalid
    end
  end

  def ids(repo, body) do
    body
    |> Kernel.||("")
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("action-text-attachment[sgid]")
    |> LazyHTML.attribute("sgid")
    |> Enum.reduce_while({:ok, []}, fn sgid, {:ok, ids} ->
      case resolve(repo, sgid) do
        {:ok, blob} -> {:cont, {:ok, [blob.id | ids]}}
        status when status in [:missing, :invalid] -> {:cont, {:ok, ids}}
        _ -> {:halt, {:replay, "trip attachment capability"}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.sort(Enum.uniq(ids))}
      error -> error
    end
  end

  def lock(repo, rich, ids) do
    old =
      if rich,
        do:
          repo.query!(
            "SELECT blob_id FROM active_storage_attachments WHERE record_type='ActionText::RichText' AND record_id=$1",
            [rich],
            log: false
          ).rows
          |> List.flatten(),
        else: []

    locked =
      repo.query!(
        "SELECT id,metadata FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id FOR UPDATE",
        [Enum.sort(Enum.uniq(old ++ ids))],
        log: false
      ).rows

    if Enum.all?(ids, fn id ->
         Enum.any?(locked, fn [blob, metadata] ->
           blob == id and not NativePurge.pending?(metadata)
         end)
       end),
       do: :ok,
       else: {:replay, "trip attachment capability"}
  end

  def sync!(repo, rich, ids, stamp) do
    old =
      repo.query!(
        "SELECT id,blob_id FROM active_storage_attachments WHERE record_type='ActionText::RichText' AND record_id=$1 AND name='embeds' ORDER BY blob_id FOR UPDATE",
        [rich],
        log: false
      ).rows

    removed =
      for [attachment, blob] <- old, blob not in ids do
        repo.query!("DELETE FROM active_storage_attachments WHERE id=$1", [attachment],
          log: false
        )

        blob
      end

    for id <- ids, id not in Enum.map(old, &List.last/1) do
      identify!(repo, id)

      repo.query!(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('embeds','ActionText::RichText',$1,$2,$3)",
        [rich, id, stamp],
        log: false
      )

      Dawarich.Trips.AnalyzeAttachmentWorker.enqueue!(repo, id)
    end

    Dawarich.Exports.PurgeWorker.enqueue!(repo, Enum.uniq(removed))
    :ok
  end

  defp identify!(repo, id) do
    [[key, filename, type, metadata, size, name]] =
      repo.query!(
        "SELECT key,filename,content_type,metadata,byte_size,service_name FROM active_storage_blobs WHERE id=$1",
        [id],
        log: false
      ).rows

    metadata = Jason.decode!(metadata || "{}")

    unless metadata["identified"] do
      service = Storage.service!(Storage.services!(System.get_env()), name)
      dir = Storage.tmp_dir!(service, "trip-identify-" <> Ecto.UUID.generate())
      path = Path.join(dir, "input")

      try do
        File.write!(path, if(size > 0, do: chunk!(service, key), else: ""))

        declared =
          if type in [nil, "application/octet-stream"], do: MIME.from_path(filename), else: type

        type = Dawarich.Storage.ImageVariant.identify(path, declared)

        repo.query!(
          "UPDATE active_storage_blobs SET metadata=$2,content_type=$3 WHERE id=$1",
          [
            id,
            Jason.encode!(Map.put(metadata, "identified", true)),
            type
          ],
          log: false
        )
      after
        File.rm_rf!(dir)
      end
    end
  end

  defp chunk!(%{service: "local", root: root}, key) do
    File.open!(Storage.disk_path(root, key), [:read, :binary], fn io ->
      case IO.binread(io, 4096) do
        :eof -> ""
        bytes when is_binary(bytes) -> bytes
        {:error, reason} -> raise File.Error, reason: reason, action: "read", path: "blob"
      end
    end)
  end

  defp chunk!(%{service: "s3"} = service, key) do
    headers = %{"range" => "bytes=0-4095"}
    url = Storage.S3.presigned_url!(service, :get, key, %{}, headers, DateTime.utc_now(), 300)

    case Storage.HttpcClient.request(:get, url, "", headers, []) do
      {:ok, %{status_code: status, body: bytes}}
      when status in [200, 206] and byte_size(bytes) <= 4096 ->
        bytes

      _ ->
        raise ArgumentError, "ActiveStorage identification read failed"
    end
  end

  def detach!(repo, ids) do
    blobs =
      repo.query!(
        "DELETE FROM active_storage_attachments WHERE record_type='ActionText::RichText' AND record_id=ANY($1::bigint[]) RETURNING blob_id",
        [ids],
        log: false
      ).rows
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort()

    Dawarich.Exports.PurgeWorker.enqueue!(repo, blobs)
  end

  def render(blob, attrs, gallery \\ false) do
    preview = Representations.representable?(blob)
    extension = blob.filename |> Path.extname() |> String.trim_leading(".")
    metadata = Jason.decode!(blob.metadata || "{}")

    additions =
      [{"content-type", blob.content_type || "application/octet-stream"}] ++
        if(preview, do: [{"previewable", "true"}], else: []) ++
        [{"filename", blob.filename}, {"filesize", to_string(blob.byte_size)}] ++
        for key <- ~w(width height), metadata[key], do: {key, to_string(metadata[key])}

    full =
      Enum.reduce(additions, attrs, fn {key, value}, acc ->
        List.keystore(acc, key, 0, {key, value})
      end)

    caption =
      if value = full |> List.keyfind("caption", 0) |> then(&(&1 && elem(&1, 1))),
        do: "    #{escape(value)}\n",
        else:
          "      <span class=\"attachment__name\">#{escape(blob.filename)}</span>\n      <span class=\"attachment__size\">#{Dawarich.CLI.RawDataStatus.human_size(blob.byte_size)}</span>\n"

    image =
      if preview, do: "    <img src=\"#{escape(representation(blob, gallery))}\">\n", else: ""

    html =
      "<figure class=\"attachment attachment--#{if preview, do: "preview", else: "file"} attachment--#{escape(extension)}\">\n#{image}\n  <figcaption class=\"attachment__caption\">\n#{caption}  </figcaption>\n</figure>"

    {full, html}
  end

  def editor(html),
    do:
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.to_tree()
      |> editor_nodes()
      |> LazyHTML.Tree.to_html()

  defp editor_nodes(nodes), do: Enum.map(nodes, &editor_node/1)

  defp editor_node({"action-text-attachment", attrs, children} = node) do
    if List.keyfind(attrs, "sgid", 0) do
      data =
        Map.new(attrs, fn {key, value} ->
          key = if key == "content-type", do: "contentType", else: key

          value =
            cond do
              key == "previewable" ->
                value == "true"

              key in ~w(filesize width height) ->
                case Integer.parse(value) do
                  {number, ""} -> number
                  _ -> value
                end

              true ->
                value
            end

          {key, value}
        end)
        |> Map.put("content", LazyHTML.Tree.to_html(children))

      composed = Map.take(data, ~w(caption presentation))
      attrs = [{"data-trix-attachment", Jason.encode!(Map.drop(data, ~w(caption presentation)))}]

      attrs =
        if map_size(composed) > 0,
          do: attrs ++ [{"data-trix-attributes", Jason.encode!(composed)}],
          else: attrs

      {"figure", attrs, []}
    else
      node
    end
  end

  defp editor_node({tag, attrs, children}), do: {tag, attrs, editor_nodes(children)}
  defp editor_node(node), do: node

  defp representation(blob, gallery) do
    extension = blob.filename |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    format =
      if blob.content_type in ~w(image/png image/jpeg image/gif image/webp image/avif),
        do:
          if(MIME.type(extension) == blob.content_type,
            do: extension,
            else: List.first(MIME.extensions(blob.content_type)) || "png"
          ),
        else: "png"

    variation =
      Variation.sign([
        {"format", format},
        {"resize_to_limit", if(gallery, do: [800, 600], else: [1024, 768])}
      ])

    "/rails/active_storage/representations/redirect/#{BlobPath.segment(RailsMessages.blob_id(blob.id))}/#{BlobPath.segment(variation)}/#{BlobPath.path(Storage.sanitized_filename(blob.filename))}"
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
