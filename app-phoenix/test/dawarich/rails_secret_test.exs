defmodule Dawarich.RailsSecretTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsSecret

  setup context do
    if context[:tmp_dir] do
      File.mkdir_p!(Path.join(context.tmp_dir, "tmp"))
      File.write!(Path.join(context.tmp_dir, "tmp/local_secret.txt"), "from-file")
    end

    :ok
  end

  @tag :tmp_dir
  test "SECRET_KEY_BASE wins over the local secret file, as in Rails", %{tmp_dir: root} do
    env = %{"SECRET_KEY_BASE" => "from-env", "RAILS_ENV" => "development"}
    assert RailsSecret.resolve(env, root) == "from-env"
  end

  @tag :tmp_dir
  test "development and test read tmp/local_secret.txt when SECRET_KEY_BASE is unset", %{
    tmp_dir: root
  } do
    for env <- [
          %{},
          %{"RAILS_ENV" => "development"},
          %{"RAILS_ENV" => "test"},
          %{"SECRET_KEY_BASE" => ""}
        ] do
      assert RailsSecret.resolve(env, root) == "from-file"
    end
  end

  @tag :tmp_dir
  test "RACK_ENV names the environment when RAILS_ENV is unset", %{tmp_dir: root} do
    assert RailsSecret.rails_env(%{"RACK_ENV" => "production"}) == "production"
    assert RailsSecret.rails_env(%{"RAILS_ENV" => "", "RACK_ENV" => "staging"}) == "staging"
    assert RailsSecret.resolve(%{"RACK_ENV" => "production"}, root) == nil
  end

  @tag :tmp_dir
  test "production and staging never read the local secret file", %{tmp_dir: root} do
    assert RailsSecret.resolve(%{"RAILS_ENV" => "production"}, root) == nil
    assert RailsSecret.resolve(%{"RAILS_ENV" => "staging"}, root) == nil
  end

  test "the endpoint secret is stable, long enough for Phoenix and not the Rails secret" do
    secret = RailsSecret.endpoint_secret("rails-secret")

    assert secret == RailsSecret.endpoint_secret("rails-secret")
    assert byte_size(Base.decode64!(secret)) == 64
    refute secret == RailsSecret.endpoint_secret("another-rails-secret")
    refute String.contains?(secret, "rails-secret")
    assert byte_size(RailsSecret.endpoint_secret(nil)) >= 64
  end
end
