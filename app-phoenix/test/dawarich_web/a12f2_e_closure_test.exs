defmodule DawarichWeb.A12f2EClosureTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Imports.Api
  alias Dawarich.Jobs.Ownership

  setup do
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "a12f2e-synthetic-checkout-not-for-production")

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    for spec <- Dawarich.Redis.child_specs() ++ Dawarich.Redis.cache_child_specs(),
        do: start_supervised!(spec)

    :ok
  end

  @tag :a12f2_e_02
  test "Import API preserves actor pagination upload type limits name uniqueness and native processing" do
    owner = user!(%{plan: 1, points_count: 0, settings: %{"timezone" => "UTC"}})
    foreign = user!()

    [[id]] =
      Repo.query!(
        "INSERT INTO imports(user_id,name,status,created_at,updated_at) VALUES($1,'foreign.json',0,now(),now()) RETURNING id",
        [foreign]
      ).rows

    assert Api.show(Repo, owner, id) == {:error, 404, %{"error" => "Record not found"}}
    ctx = context()

    user = %{
      id: owner,
      email: "a12f2e-cloud@example.invalid",
      status: 1,
      plan: 1,
      points_count: 0,
      subscription_source: 1,
      active_until: nil,
      settings: %{"timezone" => "UTC"}
    }

    assert {:ok, [], %{current_page: 1, total_pages: 0}} = Api.index(Repo, owner, %{})
    assert {:error, 422, %{"error" => missing}} = Api.create(Repo, user, %{}, ctx)
    assert missing =~ "file"
    upload = upload!("source.json", "{}")
    Ownership.put!(Repo, "command:imports.process_normal", :oban)
    assert {:ok, 201, first} = Api.create(Repo, user, %{"file" => upload}, ctx)
    assert first["source"] == nil
    assert first["status"] == "created"
    assert first["name"] == "source.json"
    assert {:ok, 201, second} = Api.create(Repo, user, %{"file" => upload}, ctx)
    assert second["name"] == "source_20261006_120000.json"

    assert {:error, 422, %{"error" => "Name has already been taken"}} =
             Api.create(Repo, user, %{"file" => upload}, ctx)

    assert {:error, 403, %{"error" => "write_api_restricted"}} =
             Api.create(Repo, %{user | plan: 0}, %{"file" => upload}, %{ctx | self_hosted?: false})

    assert {:ok, [^second], %{current_page: 1, total_pages: 2}} =
             Api.index(Repo, owner, %{"per_page" => "1"})

    assert [[2]] =
             Repo.query!(
               "SELECT count(*) FROM job_outbox WHERE command_type='imports.process_normal'"
             ).rows

    assert [["source.json", 2, "application/json"]] =
             Repo.query!(
               "SELECT b.filename,b.byte_size,b.content_type FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id WHERE a.record_type='Import' AND a.record_id=$1",
               [first["id"]]
             ).rows

    assert {:error, 422, _} =
             Api.create(Repo, user, %{"file" => %{upload | filename: "bad.exe"}}, ctx)

    assert {:error, 422, _} =
             Api.create(
               Repo,
               %{user | status: 2, subscription_source: nil},
               %{"file" => upload!("big.json", String.duplicate("x", 11 * 1024 * 1024 + 1))},
               ctx
             )
  end

  @tag :a12f2_e_03
  test "Pending intake retains Cloud only origin file quota ticket expiry storage and error outcomes" do
    alias Dawarich.PendingImports.{Intake, Quota}

    ctx =
      Map.merge(context(), %{
        origin: "https://dawarich.app",
        base_url: "https://localhost",
        zone: "Etc/UTC",
        production?: false
      })

    assert {:error, 404, nil} = Intake.create(Repo, %{}, ctx)
    ctx = %{ctx | self_hosted?: false}
    key = Quota.key(ctx.now)
    Dawarich.Redis.cache_command(["DEL", key])
    on_exit(fn -> Dawarich.Redis.cache_command(["DEL", key]) end)
    assert {:error, 403, nil} = Intake.create(Repo, %{}, %{ctx | origin: "https://evil.example"})
    assert {:error, 400, %{"error" => "Missing file"}} = Intake.create(Repo, %{}, ctx)
    file = upload!("source.json", "{}")
    params = %{"file" => file, "original_filename" => "source.json"}

    assert {:error, 422, _} =
             Intake.create(Repo, %{params | "file" => upload!("source.json", "")}, ctx)

    assert {:error, 500, _} =
             Intake.create(Repo, params, %{ctx | storage: %{service: "local", root: file.path}})

    assert {:ok, "0"} = Dawarich.Redis.cache_command(["GET", key])
    assert [[1]] = Repo.query!("SELECT count(*) FROM pending_imports").rows
    Dawarich.Redis.cache_command(["SET", key, to_string(10 * 1024 * 1024 * 1024)])
    assert {:error, 429, _} = Intake.create(Repo, params, ctx)
    assert {:ok, to_string(10 * 1024 * 1024 * 1024)} == Dawarich.Redis.cache_command(["GET", key])
    Dawarich.Redis.cache_command(["SET", key, "0"])
    assert {:ok, 201, result} = Intake.create(Repo, params, ctx)
    assert {:ok, _} = Ecto.UUID.cast(result["claim_ticket"])
    assert result["expires_at"] == "2026-10-07T12:00:00Z"

    assert result["claim_url"] ==
             "https://localhost/users/sign_up?import_ticket=#{result["claim_ticket"]}&utm_source=tool&utm_medium=save-to-account"

    assert [["source.json", "https://dawarich.app", nil]] =
             Repo.query!(
               "SELECT original_filename,origin,claimed_at FROM pending_imports WHERE claim_ticket=$1",
               [Ecto.UUID.dump!(result["claim_ticket"])]
             ).rows

    assert {:ok, "2"} = Dawarich.Redis.cache_command(["GET", key])
    assert [] == commands()
  end

  defp context do
    root = Path.join(System.tmp_dir!(), "a12f2e-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{self_hosted?: true, now: ~U[2026-10-06 12:00:00Z], storage: %{service: "local", root: root}}
  end

  defp upload!(name, data) do
    path = Path.join(System.tmp_dir!(), "a12f2e-upload-#{System.unique_integer([:positive])}")
    File.write!(path, data)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: name, content_type: "application/json"}
  end
end
