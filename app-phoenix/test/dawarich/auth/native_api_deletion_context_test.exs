defmodule Dawarich.Auth.NativeApiDeletionContextTest do
  use Dawarich.IngestCase, async: true
  alias Dawarich.Auth.AccountDestroy
  @now ~U[2026-10-03 12:00:00Z]

  test "native API deletion uses its request database clock and durable owner without a mode switch" do
    id = user!(%{provider: "openid_connect", email: "native-context@example.invalid"})

    context =
      AccountDestroy.context(%{
        repo: Repo,
        clock: fn -> @now end,
        native_api: true,
        self_hosted: true
      })

    assert {:ok, :scheduled} =
             AccountDestroy.request(
               id,
               %{"confirm_email" => "native-context@example.invalid"},
               context
             )

    assert [[~N[2026-10-03 12:00:00.000000]]] =
             Repo.query!("SELECT deleted_at FROM users WHERE id=$1", [id]).rows

    assert [["users.destroy", %{"user_id" => ^id}]] =
             Repo.query!("SELECT command_type,payload FROM job_outbox WHERE aggregate_id=$1", [id]).rows
  end
end
