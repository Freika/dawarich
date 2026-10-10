defmodule DawarichWeb.DigestsNativeActionsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.{Repo, Accounts.Scope, Digests.Commands}
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint

  setup do
    %{target: user} = NativeAdminUI.setup!()
    stat!(user.id, %{year: 2024, month: 3})
    %{user: user, scope: Scope.for_user(user, "en")}
  end

  test "digest generation excludes current year and duplicates publish once", %{
    scope: scope,
    user: user
  } do
    stat!(user.id, %{year: Date.utc_today().year, month: 1})
    receipt = Ecto.UUID.generate()

    assert {:error, :invalid_input} =
             Commands.generate(scope, %{"year" => to_string(Date.utc_today().year)}, receipt)

    assert {:ok, %{year: 2024}} = Commands.generate(scope, %{"year" => "2024"}, receipt)
    assert {:ok, %{year: 2024}} = Commands.generate(scope, %{"year" => "2024"}, receipt)

    assert Repo.query!(
             "SELECT payload->>'year',metadata->>'producer' FROM public.job_outbox WHERE command_type='digests.calculate_year'",
             [],
             log: false
           ).rows == [["2024", "Users::DigestsController"]]

    assert Repo.query!("SELECT id FROM digests WHERE user_id=$1", [user.id], log: false).rows ==
             []

    retry_receipt = Ecto.UUID.generate()

    Repo.query!(
      "ALTER TABLE public.job_outbox ADD CONSTRAINT native_digest_failure CHECK(command_type!='digests.calculate_year') NOT VALID",
      [],
      log: false
    )

    assert {:error, :unavailable} = Commands.generate(scope, %{"year" => "2024"}, retry_receipt)
    key = "native-digest-generation:#{user.id}:#{retry_receipt}:2024"

    assert Repo.query!("SELECT key FROM phoenix.once_claims WHERE key=$1", [key], log: false).rows ==
             []

    Repo.query!("ALTER TABLE public.job_outbox DROP CONSTRAINT native_digest_failure", [],
      log: false
    )

    assert {:ok, %{year: 2024}} = Commands.generate(scope, %{"year" => "2024"}, retry_receipt)

    assert Repo.query!(
             "SELECT count(*) FROM public.job_outbox WHERE command_type='digests.calculate_year'",
             [],
             log: false
           ).rows == [[2]]

    Repo.query!("UPDATE users SET status=0 WHERE id=$1", [user.id], log: false)

    assert {:error, :inactive} =
             Commands.generate(scope, %{"year" => "2024"}, Ecto.UUID.generate())
  end

  test "digest deletion preserves other years and errors in place", %{user: user} do
    digest!(10801, %{year: 2024})
    digest!(user.id, %{year: 2024})
    digest!(user.id, %{year: 2023})
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/digests/2024")
    render_click(view, "delete", %{})
    assert has_element?(view, "#digest-delete-dialog[role=dialog]")
    render_click(view, "cancel_delete", %{})

    assert Repo.query!("SELECT count(*) FROM digests WHERE user_id=$1", [user.id], log: false).rows ==
             [[2]]

    render_click(view, "delete", %{})
    render_click(view, "confirm_delete", %{})
    assert_redirect(view, "/digests")

    assert Repo.query!("SELECT year FROM digests WHERE user_id=$1", [user.id], log: false).rows ==
             [[2023]]

    assert Repo.query!("SELECT year FROM digests WHERE user_id=10801", [], log: false).rows == [
             [2024]
           ]

    {:ok, other, _} = live(NativeAdminUI.conn(user), "/digests/2023")
    render_click(other, "confirm_delete", %{})
    assert has_element?(other, "[role=alert]")

    assert Repo.query!("SELECT year FROM digests WHERE user_id=$1", [user.id], log: false).rows ==
             [[2023]]
  end

  test "digest sharing preserves expiration and rejects replaced identity", %{
    scope: scope,
    user: user
  } do
    digest!(user.id, %{year: 2024})
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    for hours <- [1, 12, 24] do
      assert {:ok, result} =
               Commands.share(
                 scope,
                 %{"year" => "2024"},
                 %{"enabled" => "1", "expiration" => "#{hours}h"},
                 now: now,
                 base_url: "https://example.invalid"
               )

      assert {:ok, expiry, _} = DateTime.from_iso8601(result.expires_at)
      assert DateTime.diff(expiry, now) == hours * 3600
      assert result.url =~ "/shared/digest/"
    end

    assert {:ok, %{enabled: false, url: ""}} =
             Commands.share(scope, %{"year" => "2024"}, %{"enabled" => "0", "expiration" => "24h"})

    Repo.query!(
      "UPDATE users SET encrypted_password='replaced-digest-identity-00000000' WHERE id=$1",
      [user.id],
      log: false
    )

    assert {:error, :stale_session} =
             Commands.share(scope, %{"year" => "2024"}, %{"enabled" => "1", "expiration" => "1h"})
  end
end
