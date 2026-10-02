defmodule DawarichWeb.ImportsController do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Imports.{Uploads, UploadCreate, Tempfiles}
  alias DawarichWeb.{ImportsContext, RequestURL, RailsSession, Translate}
  def init(action), do: action

  def call(conn, :direct_upload) do
    case Uploads.reserve(
           ImportsContext.repo(),
           conn.assigns.current_user,
           conn.params["blob"] || %{},
           ImportsContext.storage()
         ) do
      {:ok, blob} ->
        json(conn, 200, %{
          id: blob.id,
          filename: blob["filename"],
          byte_size: blob["byte_size"],
          checksum: blob["checksum"],
          content_type: blob["content_type"],
          signed_id: blob.signed_id,
          direct_upload: %{
            url: RequestURL.base(conn) <> "/imports/uploads/" <> blob.upload_token,
            headers: %{"Content-Type" => blob["content_type"], "Content-MD5" => blob["checksum"]}
          }
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def call(conn, :upload) do
    user = conn.assigns.current_user
    token = conn.path_params["token"]

    case Uploads.upload_info(ImportsContext.repo(), user, token) do
      {:ok, blob} ->
        Tempfiles.with_files(fn adopt ->
          path = Path.join(System.tmp_dir!(), "upload-" <> Ecto.UUID.generate())
          file = File.open!(path, [:write, :binary, :exclusive])
          File.chmod!(path, 0o600)
          adopt.(path)

          result =
            try do
              read_upload(conn, file, blob.byte_size, 0)
            after
              File.close(file)
            end

          case result do
            {:ok, conn} ->
              case Uploads.write(
                     ImportsContext.repo(),
                     user,
                     token,
                     path,
                     ImportsContext.storage()
                   ) do
                :ok -> send_resp(conn, 204, "")
                {:error, reason} -> error(conn, reason)
              end

            {:error, conn} ->
              error(conn, :integrity)
          end
        end)

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def call(conn, :create) do
    user = conn.assigns.current_user
    params = import_params(conn)

    case UploadCreate.create(
           ImportsContext.repo(),
           user,
           params["files"] || [],
           ImportsContext.for_user(user)
         ) do
      {:ok, ids} ->
        locale = Dawarich.Mail.ExploreFeatures.locale(user.settings, nil)

        notice =
          Translate.t(
            locale,
            "controllers.imports.size_files_are_queued_to_be_imported_in_background",
            %{"size" => length(ids)}
          )

        conn
        |> RailsSession.stage(%{
          "flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}
        })
        |> put_resp_header("location", RequestURL.base(conn) <> "/imports")
        |> send_resp(303, "")

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def call(conn, :update) do
    case conn.params["_method"] do
      method when method in ["delete", "DELETE"] ->
        call(conn, :delete)

      method when method in [nil, "patch", "PATCH"] ->
        case Dawarich.Imports.UiRecords.update(
               ImportsContext.repo(),
               conn.assigns.current_user.id,
               conn.path_params["id"],
               import_params(conn)
             ) do
          {:ok, _} ->
            conn
            |> put_resp_header("location", RequestURL.base(conn) <> "/imports")
            |> send_resp(303, "")

          {:error, reason} ->
            error(conn, reason)
        end

      _ ->
        error(conn, :invalid_method)
    end
  end

  def call(conn, :delete) do
    user = conn.assigns.current_user

    case DawarichWeb.ImportsActions.delete(user, conn.path_params["id"]) do
      {:ok, _} ->
        conn
        |> put_resp_header("location", RequestURL.base(conn) <> "/imports")
        |> send_resp(303, "")

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def call(conn, :extract) do
    if conn.params["_method"] in ["delete", "DELETE"],
      do: call(conn, :remove_extraction),
      else: extract(conn)
  end

  def call(conn, :remove_extraction) do
    user = conn.assigns.current_user

    case Dawarich.Imports.UiRecords.remove_extraction(
           ImportsContext.repo(),
           user.id,
           conn.path_params["id"],
           ImportsContext.for_user(user)
         ) do
      {:ok, _} ->
        conn
        |> put_resp_header(
          "location",
          RequestURL.base(conn) <> "/imports/" <> conn.path_params["id"]
        )
        |> send_resp(303, "")

      {:error, reason} ->
        error(conn, reason)
    end
  end

  defp extract(conn) do
    user = conn.assigns.current_user

    case Dawarich.Imports.UiRecords.extract(
           ImportsContext.repo(),
           user.id,
           conn.path_params["id"],
           conn.params,
           ImportsContext.for_user(user)
         ) do
      {:ok, _} ->
        conn
        |> put_resp_header(
          "location",
          RequestURL.base(conn) <> "/imports/" <> conn.path_params["id"]
        )
        |> send_resp(303, "")

      {:error, reason} ->
        error(conn, reason)
    end
  end

  defp import_params(conn),
    do: if(is_map(conn.params["import"]), do: conn.params["import"], else: %{})

  defp read_upload(conn, file, expected, received) do
    case read_body(conn, length: 65_536, read_length: 65_536, read_timeout: 15_000) do
      {status, bytes, conn} when status in [:ok, :more] ->
        total = received + byte_size(bytes)

        if total > expected do
          {:error, conn}
        else
          :ok = IO.binwrite(file, bytes)

          if status == :more,
            do: read_upload(conn, file, expected, total),
            else: if(total == expected, do: {:ok, conn}, else: {:error, conn})
        end

      {:error, _} ->
        {:error, conn}
    end
  end

  defp error(conn, reason),
    do:
      json(conn, if(reason in [:forbidden, :not_found], do: 404, else: 422), %{
        error: to_string(reason)
      })

  defp json(conn, status, body),
    do:
      conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
end
