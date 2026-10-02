defmodule Dawarich.Storage.ImportServicesTest do
  use ExUnit.Case, async: true
  alias Dawarich.Storage.{ImportServices, Reader}

  @aws %{
    "AWS_ACCESS_KEY_ID" => "synthetic",
    "AWS_SECRET_ACCESS_KEY" => "synthetic-secret",
    "AWS_REGION" => "eu-central-1",
    "AWS_BUCKET" => "dawarich"
  }

  setup do
    root = Path.join(System.tmp_dir!(), "import-services-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "config"))
    File.cp!("../config/storage.yml", Path.join(root, "config/storage.yml"))
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "reads the actual Rails storage file and preserves test and local names", %{root: root} do
    services = ImportServices.configured!(%{"RAILS_ENV" => "test"}, root)

    assert services["test"] == %{
             service: "local",
             stored_service: "test",
             root: Path.join(root, "tmp/storage")
           }

    assert services["local"].root == Path.join(root, "storage")
    refute Map.has_key?(services, "s3")

    assert {:ok, services["test"]} ==
             ImportServices.resolve(services, %{service_name: "test", key: "abcdkey"})
  end

  test "historical S3 remains configured when the current backend switches to local", %{
    root: root
  } do
    services =
      ImportServices.configured!(
        Map.merge(@aws, %{"RAILS_ENV" => "production", "STORAGE_BACKEND" => "local"}),
        root
      )

    assert services["local"].service == "local"
    assert services["s3"].service == "s3"
    assert services["s3"].stored_service == "s3"
    assert services["s3"].bucket == "dawarich"
  end

  test "Rails test precedence suppresses S3 despite credentials and RACK_ENV", %{root: root} do
    services =
      ImportServices.configured!(
        Map.merge(@aws, %{"RAILS_ENV" => "test", "RACK_ENV" => "production"}),
        root
      )

    refute Map.has_key?(services, "s3")

    assert Map.has_key?(
             ImportServices.configured!(Map.put(@aws, "RACK_ENV", "production"), root),
             "s3"
           )
  end

  test "missing credentials or undeclared services return explicit legacy", %{root: root} do
    services = ImportServices.configured!(Map.delete(@aws, "AWS_REGION"), root)

    assert {:legacy, :unconfigured_storage_service} =
             ImportServices.resolve(services, %{service_name: "s3", key: "abcd"})

    assert {:legacy, :unconfigured_storage_service} =
             ImportServices.resolve(services, %{service_name: "old", key: "abcd"})
  end

  test "literal historical disk and S3 aliases resolve their declared configuration", %{
    root: root
  } do
    File.write!(Path.join(root, "config/storage.yml"), """
    archive:
      service: Disk
      root: "#{root}/archive"
    cloud_archive:
      service: S3
      access_key_id: <%= ENV.fetch("AWS_ACCESS_KEY_ID") %>
      secret_access_key: <%= ENV.fetch("AWS_SECRET_ACCESS_KEY") %>
      region: eu-central-1
      bucket: archived-bucket
      force_path_style: true
    """)

    services = ImportServices.configured!(@aws, root)
    assert services["archive"].root == Path.join(root, "archive")
    assert services["cloud_archive"].bucket == "archived-bucket"
    assert services["cloud_archive"].ex_aws[:virtual_host] == false
    assert :ok = Reader.admit(services["archive"], %{service_name: "archive", key: "abcdkey"})
  end

  test "unsupported Ruby expressions are never evaluated or guessed", %{root: root} do
    marker = Path.join(root, "executed")

    File.write!(Path.join(root, "config/storage.yml"), """
    old:
      service: Disk
      root: <%= File.write("#{marker}", "bad") %>
    relative:
      service: Disk
      root: relative/storage
    """)

    assert ImportServices.configured!(%{}, root) == %{}
    refute File.exists?(marker)
  end

  test "unknown conditional configurations are refused", %{root: root} do
    File.write!(Path.join(root, "config/storage.yml"), """
    <% if ENV['CUSTOM'] %>
    old:
      service: Disk
      root: <%= Rails.root.join("old") %>
    <% end %>
    """)

    assert ImportServices.configured!(%{"CUSTOM" => "true"}, root) == %{}
  end

  test "unrepresentable endpoints and unsupported services cannot be silently rerouted", %{
    root: root
  } do
    for endpoint <- [
          "https://user:secret@example.test",
          "https://example.test/prefix",
          "https://example.test?token=secret",
          "https://example.test#fragment"
        ] do
      services = ImportServices.configured!(Map.put(@aws, "AWS_ENDPOINT_URL", endpoint), root)
      refute Map.has_key?(services, "s3")
    end

    File.write!(
      Path.join(root, "config/storage.yml"),
      "mirror:\n  service: Mirror\n  primary: local\n"
    )

    assert ImportServices.configured!(%{}, root) == %{}
  end

  test "unknown executable directives cannot alter the interpretation of later roots", %{
    root: root
  } do
    File.write!(Path.join(root, "config/storage.yml"), """
    <% Rails.root = Pathname.new('/other') %>
    local:
      service: Disk
      root: <%= Rails.root.join("storage") %>
    """)

    assert ImportServices.configured!(%{}, root) == %{}
  end

  test "absolute Rails.root.join arguments do not silently use a different root", %{root: root} do
    File.write!(Path.join(root, "config/storage.yml"), """
    archive:
      service: Disk
      root: <%= Rails.root.join("/declared/archive") %>
    """)

    assert ImportServices.configured!(%{}, root)["archive"].root == "/declared/archive"
  end

  test "unsupported bucket addressing is refused rather than interpolated into a URL", %{
    root: root
  } do
    for bucket <- ["bucket/path", "bucket?query", "arn:aws:s3:accesspoint", "bucket#fragment"] do
      refute Map.has_key?(
               ImportServices.configured!(Map.put(@aws, "AWS_BUCKET", bucket), root),
               "s3"
             )
    end
  end

  test "key admission is explicit before any import effects", %{root: root} do
    services = ImportServices.configured!(%{}, root)

    assert {:legacy, :unsafe_storage_key} =
             ImportServices.resolve(services, %{service_name: "local", key: "../secret"})

    assert {:legacy, :storage_service_mismatch} =
             Reader.admit(services["local"], %{service_name: "test", key: "abcd"})
  end
end
