defmodule Dawarich.UserDataParityTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser
  alias Dawarich.UserData
  alias DawarichWeb.Translate

  @http Path.expand("../fixtures/user_data/http.json", __DIR__)
  @prefix "controllers.settings.users."
  @outcomes %{
    :ok => {"notice", "your_data_import_has_been_started_you_will_receive_a"},
    {:error, :blank} => {"alert", "please_select_a_zip_archive_to_import"},
    {:error, :validation} => {"alert", "failed_to_start_import_please_try_again"},
    {:error, :invalid_archive} =>
      {"alert", "an_error_occurred_while_starting_the_import_please_try_again"}
  }

  @moduletag :tmp_dir
  setup %{tmp_dir: dir} do
    RailsUser.insert!(%{
      id: 9891,
      email: "backup-boundary@example.invalid",
      admin: false,
      status: 0,
      active_until: ~N[2020-01-01 00:00:00],
      settings: %{"timezone" => "UTC", "locale" => "en"}
    })

    Ownership.put!(Repo, "command:users.export_data", :oban)
    Ownership.put!(Repo, "command:users.import_data", :oban)
    %{root: dir, expected: File.read!(@http) |> Jason.decode!()}
  end

  defp scope(locale), do: Scope.for_user(Dawarich.Accounts.get(9891), locale)

  defp blob(c, name),
    do:
      Dawarich.RailsBlobFixture.create!(Repo, c.root, name, "synthetic ZIP",
        content_type: "application/zip",
        user_id: 9891
      )

  defp counts,
    do:
      Repo.query!(
        "SELECT (SELECT count(*) FROM imports),(SELECT count(*) FROM active_storage_attachments),(SELECT count(*) FROM job_outbox)"
      ).rows

  defp assert_recorded(locale, result, recorded) do
    {kind, key} = Map.fetch!(@outcomes, result)
    assert recorded["flash"] == %{kind => Translate.t(locale, @prefix <> key, %{})}
  end

  test "import and export outcomes equal Rails' recorded answers in all shipped locales", c do
    for locale <- ~w(en de es fr pl ca zh) do
      expected = c.expected[locale]

      assert :ok = UserData.request_export(scope(locale))

      assert expected["export"]["flash"] == %{
               "notice" =>
                 Translate.t(
                   locale,
                   @prefix <> "your_data_is_being_exported_you_will_receive_a_notification",
                   %{}
                 )
             }

      blank = UserData.start_import(scope(locale), "")
      assert blank == {:error, :blank}
      assert_recorded(locale, blank, expected["blank"])

      invalid = UserData.start_import(scope(locale), "invalid")
      assert invalid == {:error, :invalid_archive}
      assert_recorded(locale, invalid, expected["invalid"])

      file = blob(c, locale <> "-backup.zip")
      valid = UserData.start_import(scope(locale), file.signed_id)
      assert valid == :ok
      assert_recorded(locale, valid, expected["valid"])

      Repo.query!("UPDATE active_storage_blobs SET filename='' WHERE id=$1", [file.id])
      failed = UserData.start_import(scope(locale), file.signed_id)
      assert failed == {:error, :validation}
      assert_recorded(locale, failed, expected["failed"])
    end

    assert commands() == []
  end

  test "legacy trial count and size boundaries equal Rails' recorded answers", c do
    for locale <- ~w(en de es fr pl ca zh) do
      Repo.query!("DELETE FROM active_storage_attachments")
      Repo.query!("DELETE FROM imports")
      Repo.query!("DELETE FROM job_outbox")

      Repo.query!(
        "UPDATE users SET status=2,subscription_source=0,settings=jsonb_set(settings,'{locale}',$1::text::jsonb) WHERE id=9891",
        [Jason.encode!(locale)]
      )

      Repo.query!(
        "INSERT INTO imports(user_id,name,created_at,updated_at) SELECT 9891,'trial boundary '||n,now(),now() FROM generate_series(1,4) n"
      )

      Repo.query!(
        "INSERT INTO imports(user_id,name,demo,created_at,updated_at) VALUES(9891,'demo boundary',true,now(),now())"
      )

      file = blob(c, "trial.zip")

      Repo.query!("UPDATE active_storage_blobs SET byte_size=$1 WHERE id=$2", [
        11 * 1024 * 1024,
        file.id
      ])

      for boundary <- ~w(count_four count_five size_limit size_over subscribed) do
        Repo.query!("UPDATE active_storage_blobs SET filename=$1 WHERE id=$2", [
          locale <> "-" <> boundary <> ".zip",
          file.id
        ])

        if boundary == "size_limit", do: Repo.query!("UPDATE imports SET demo=true")

        if boundary == "size_over",
          do:
            Repo.query!("UPDATE active_storage_blobs SET byte_size=$1 WHERE id=$2", [
              11 * 1024 * 1024 + 1,
              file.id
            ])

        if boundary == "subscribed" do
          Repo.query!("UPDATE users SET subscription_source=1 WHERE id=9891")

          Repo.query!(
            "INSERT INTO imports(user_id,name,created_at,updated_at) SELECT 9891,'subscribed boundary '||n,now(),now() FROM generate_series(1,5) n"
          )
        end

        [[imports, attachments, jobs]] = counts()
        expected = c.expected[locale]["trial"][boundary]
        result = UserData.start_import(scope(locale), file.signed_id)
        assert_recorded(locale, result, expected)

        assert counts() == [
                 [
                   imports + expected["imports_created"],
                   attachments + expected["attachments_created"],
                   jobs + expected["jobs_created"]
                 ]
               ]
      end
    end

    assert commands() == []
  end

  test "a second archive with the same name gets a timestamped name", c do
    first = blob(c, "backup.zip")
    second = blob(c, "backup.zip")

    assert :ok = UserData.start_import(scope("en"), first.signed_id)
    assert :ok = UserData.start_import(scope("en"), second.signed_id)

    assert [["backup.zip"], [renamed]] =
             Repo.query!("SELECT name FROM imports WHERE user_id=9891 ORDER BY id").rows

    assert renamed =~ ~r/\Abackup_\d{8}_\d{6}\.zip\z/
  end

  test "Sidekiq-owned exports and imports become Rails commands with the same payload", c do
    Ownership.put!(Repo, "command:users.export_data", :sidekiq)
    Ownership.put!(Repo, "command:users.import_data", :sidekiq)

    assert :ok = UserData.request_export(scope("en"))
    assert :ok = UserData.start_import(scope("en"), blob(c, "other.zip").signed_id)

    assert [
             ["users.export_data", %{"user_id" => 9891, "time_zone" => "UTC", "locale" => "en"}],
             ["users.import_data", %{"import_id" => _, "user_id" => 9891}]
           ] = commands()
  end
end
