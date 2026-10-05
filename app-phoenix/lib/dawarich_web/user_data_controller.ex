defmodule DawarichWeb.UserDataController do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{Locale, RailsSession, RequestURL, Translate, ImportsContext}
  alias Dawarich.Imports.Uploads
  alias Dawarich.UserData.ImportCommands
  alias Dawarich.Jobs.Ownership
  @prefix "controllers.settings.users."

  def init(action), do: action

  def call(conn, :export) do
    user = conn.assigns.current_user
    repo = ImportsContext.repo()
    context = context(conn)

    {:ok, :ok} =
      repo.transaction(fn ->
        payload = %{"user_id" => user.id, "time_zone" => context.zone, "locale" => context.locale}

        if Ownership.lock(repo, "command:users.export_data") == :oban do
          repo.query!(
            "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),'users.export_data',1,$1,$2,$3,now())",
            [payload, %{"producer" => "Phoenix SettingsUsersExport"}, user.id],
            log: false
          )
        else
          Dawarich.RailsCommands.insert!(repo, "users.export_data", payload)
        end

        :ok
      end)

    redirect(
      conn,
      "/exports",
      "notice",
      "your_data_is_being_exported_you_will_receive_a_notification"
    )
  end

  def call(conn, :import) do
    value = conn.assigns.api_params["archive"]

    cond do
      is_nil(value) or (is_binary(value) and String.trim(value) == "") ->
        redirect(conn, "/users/edit", "alert", "please_select_a_zip_archive_to_import")

      not is_binary(value) ->
        DawarichWeb.Api.Body.replay(conn, "archive parameter")

      true ->
        start_import(conn, value)
    end
  end

  defp start_import(conn, value) do
    repo = ImportsContext.repo()
    user = conn.assigns.current_user
    context = context(conn)

    result =
      repo.transaction(fn ->
        Ownership.lock(repo, "command:users.import_data")

        [[status, subscription]] =
          repo.query!(
            "SELECT status,subscription_source FROM users WHERE id=$1 FOR UPDATE",
            [user.id],
            log: false
          ).rows

        with {:ok, blob} <- Uploads.fetch(repo, value), true <- zip?(blob) do
          if status == 2 and subscription == 0 and
               (blob.byte_size > 11 * 1024 * 1024 or trial_count(repo, user.id) >= 5),
             do: repo.rollback(:validation)

          name = unique_name(repo, user.id, blob.filename, context.zone)

          if String.trim(name) == "" or exists?(repo, user.id, name),
            do: repo.rollback(:validation)

          [[id]] =
            repo.query!(
              "INSERT INTO imports(user_id,name,source,status,additional_data_extraction_status,created_at,updated_at) VALUES($1,$2,8,0,5,now(),now()) RETURNING id",
              [user.id, name],
              log: false
            ).rows

          repo.query!(
            "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now())",
            [id, blob.id],
            log: false
          )

          ImportCommands.enqueue(repo, %{id: id, user_id: user.id}, context)
        else
          _ -> repo.rollback(:invalid_archive)
        end
      end)

    key =
      case result do
        {:ok, _} -> {"notice", "your_data_import_has_been_started_you_will_receive_a"}
        {:error, :validation} -> {"alert", "failed_to_start_import_please_try_again"}
        {:error, _} -> {"alert", "an_error_occurred_while_starting_the_import_please_try_again"}
      end

    redirect(conn, "/users/edit", elem(key, 0), elem(key, 1))
  rescue
    _ ->
      redirect(
        conn,
        "/users/edit",
        "alert",
        "an_error_occurred_while_starting_the_import_please_try_again"
      )
  end

  defp zip?(blob),
    do:
      blob.content_type in ["application/zip", "application/x-zip-compressed"] or
        String.downcase(Path.extname(blob.filename)) == ".zip"

  defp trial_count(repo, user) do
    [[count]] =
      repo.query!("SELECT count(*) FROM imports WHERE user_id=$1 AND demo=false", [user],
        log: false
      ).rows

    count
  end

  defp exists?(repo, user, name),
    do:
      repo.query!("SELECT 1 FROM imports WHERE user_id=$1 AND name=$2", [user, name], log: false).rows !=
        []

  defp unique_name(repo, user, name, zone) do
    if exists?(repo, user, name) do
      [[stamp]] =
        repo.query!(
          "SELECT to_char(now() AT TIME ZONE $1,'YYYYMMDD_HH24MISS')",
          [Dawarich.TimeZoneName.to_iana(zone)],
          log: false
        ).rows

      Path.rootname(Path.basename(name)) <> "_" <> stamp <> Path.extname(name)
    else
      name
    end
  end

  defp captured_zone(settings) do
    zone = settings["timezone"] || System.get_env("TIME_ZONE", "Europe/Berlin")
    Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    zone
  rescue
    _ -> Dawarich.UserTimeZone.name(settings, ImportsContext.repo())
  end

  defp context(conn),
    do: %{
      zone: captured_zone(conn.assigns.current_user.settings),
      locale: Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
    }

  defp redirect(conn, path, kind, key) do
    message = Translate.t(context(conn).locale, @prefix <> key, %{})

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{kind => message}}})
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("x-dawarich-handler", "phoenix-user-data")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
