defmodule DawarichWeb.Api.AccountDestroyController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Auth.AccountDestroy
  alias DawarichWeb.Api.Respond

  def init(opts), do: opts

  def call(conn, _opts) do
    context =
      Application.get_env(:dawarich, :account_destroy_context, %{})
      |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED", "true") != "false")
      |> Map.put_new(:base_url, DawarichWeb.RequestURL.base(conn))

    case AccountDestroy.request(conn.assigns.api_user.id, conn.assigns.api_params, context) do
      {:ok, :scheduled} ->
        Respond.json(conn, 200, {:object, [{"message", message("deletion_scheduled")}]})

      {:ok, :sent} ->
        Respond.json(
          conn,
          202,
          {:object,
           [
             {"message",
              "A confirmation email has been sent. Click the link in the email to permanently delete your account."}
           ]}
        )

      {:error, :password_required} ->
        Respond.json(
          conn,
          401,
          {:object, [{"error", "password_required"}, {"message", "Confirm with your password."}]}
        )

      {:error, :cannot_delete_account} ->
        Respond.json(
          conn,
          422,
          {:object, [{"error", "cannot_delete_account"}, {"message", message("cannot_delete")}]}
        )

      {:error, :rate_limited} ->
        Respond.json(
          conn,
          429,
          {:object,
           [
             {"error", "rate_limited"},
             {"message",
              "A confirmation email was already sent recently. Check your inbox or wait an hour before requesting another one."}
           ]}
        )

      {:error, _} ->
        Respond.json(conn, 503, {:object, [{"error", "account_deletion_unavailable"}]})
    end
  end

  defp message(key), do: Dawarich.I18n.en!("controllers.api.v1.users.destroy." <> key)
end
