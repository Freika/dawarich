defmodule DawarichWeb.ImportsController do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Imports.{UiRecords, UploadCreate}
  alias DawarichWeb.{ImportsActions, ImportsContext, Locale, RailsSession, RequestURL, Translate}
  alias DawarichWeb.Api.Body

  def init(action), do: action

  def call(conn, :create) do
    if method(conn) == "POST", do: create(conn), else: replay(conn, "method override")
  end

  def call(conn, :update) do
    case method(conn) do
      "DELETE" -> call(conn, :delete)
      method when method in ["PATCH", "PUT"] -> update(conn)
      _ -> replay(conn, "method override")
    end
  end

  def call(conn, :delete) do
    case ImportsActions.delete(conn.assigns.current_user, conn.path_params["id"]) do
      {:ok, _} ->
        redirect(conn, 303, "/imports", "controllers.imports.import_is_being_deleted", %{})

      {:error, reason} ->
        replay(conn, reason)
    end
  end

  def call(conn, :extract) do
    case method(conn) do
      "DELETE" -> call(conn, :remove_extraction)
      "POST" -> extraction(conn, :extract, "extraction_queued")
      _ -> replay(conn, "method override")
    end
  end

  def call(conn, :remove_extraction),
    do: extraction(conn, :remove_extraction, "removing_extracted_data")

  defp create(conn) do
    user = conn.assigns.current_user
    files = import_params(conn)["files"] || []

    case UploadCreate.create(ImportsContext.repo(), user, files, ImportsContext.for_user(user)) do
      {:ok, ids} ->
        notice = "controllers.imports.size_files_are_queued_to_be_imported_in_background"
        redirect(conn, 303, "/imports", notice, %{"size" => length(ids)})

      {:error, reason} ->
        replay(conn, reason)
    end
  end

  defp update(conn) do
    user = conn.assigns.current_user

    case UiRecords.update(
           ImportsContext.repo(),
           user.id,
           conn.path_params["id"],
           import_params(conn)
         ) do
      {:ok, _} ->
        notice = "controllers.imports.import_was_successfully_updated"
        redirect(conn, 303, "/imports", notice, %{})

      {:error, reason} ->
        replay(conn, reason)
    end
  end

  defp extraction(conn, action, key) do
    user = conn.assigns.current_user
    id = conn.path_params["id"]
    context = ImportsContext.for_user(user)

    result =
      if action == :extract,
        do: UiRecords.extract(ImportsContext.repo(), user.id, id, conn.params, context),
        else: UiRecords.remove_extraction(ImportsContext.repo(), user.id, id, context)

    case result do
      {:ok, _} ->
        redirect(conn, 302, "/imports/" <> id, "controllers.imports.extractions." <> key, %{})

      {:error, reason} ->
        replay(conn, reason)
    end
  end

  defp method(%{method: "POST", params: %{"_method" => override}}), do: String.upcase(override)
  defp method(%{method: method}), do: method

  defp redirect(conn, status, path, key, bindings) do
    user = conn.assigns.current_user
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)
    notice = Translate.t(locale, key, bindings)

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}})
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(status, "")
    |> halt()
  end

  defp replay(conn, reason), do: Body.replay(conn, "imports #{reason}")

  defp import_params(conn),
    do: if(is_map(conn.params["import"]), do: conn.params["import"], else: %{})
end
