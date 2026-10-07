defmodule DawarichWeb.FamilyDeliveryAdmission do
  @moduledoc false
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.method == "POST" and
         conn.request_path =~ ~r|\A/family/invitations(?:\.[^/]+)?\z| and
         not Dawarich.Standalone.enabled?() and not native_mail?() do
      DawarichWeb.Api.Body.replay(conn, "family invitation mail owner")
    else
      conn
    end
  end

  defp native_mail? do
    Dawarich.Repo.query!(
      "SELECT owner FROM phoenix.job_owners WHERE key=$1",
      ["command:mail.family_invitation"],
      log: false
    ).rows == [["oban"]]
  rescue
    _ -> false
  end
end
