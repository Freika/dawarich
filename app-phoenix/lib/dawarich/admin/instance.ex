defmodule Dawarich.Admin.Instance do
  @moduledoc false

  alias Dawarich.Admin.{Access, InstancePage, InstanceWrites, JobHealth}
  alias Dawarich.Accounts.Scope

  def page(%Scope{} = scope, section, opts \\ []) do
    with {:ok, scope} <- Access.admit(scope, :admin, admit_opts(opts)),
         {:ok, data} <- InstancePage.load(repo(opts), env(opts)) do
      {:ok,
       %{
         scope: scope,
         data: data,
         section: InstancePage.section(data, section),
         health: health(opts)
       }}
    end
  end

  def save(scope, params, opts \\ [])

  def save(%Scope{} = scope, %{"section" => section} = params, opts) do
    with {:ok, scope} <- Access.admit(scope, :admin, admit_opts(opts, write: true)),
         true <- section in InstancePage.sections() || {:error, :invalid_section} do
      settings = map(params["instance_settings"])

      input = %{
        "instance_settings" =>
          for(
            key <- InstancePage.field_order(section),
            Map.has_key?(settings, key),
            do: {key, settings[key]}
          ),
        "instance_settings_clear" => map(params["instance_settings_clear"])
      }

      scope.user |> InstanceWrites.call(input, context(scope, opts)) |> saved()
    end
  end

  def save(_scope, _params, _opts), do: {:error, :invalid_section}

  def test_geocoding(%Scope{} = scope, opts \\ []) do
    with {:ok, scope} <- Access.admit(scope, :admin, admit_opts(opts, write: true)) do
      case InstanceWrites.test_geocoding(scope.user, context(scope, opts)) do
        {:ok, kind, message} -> {kind, message}
        {:handoff, :oidc} -> {:error, :oidc}
        {:handoff, _} -> {:error, :unauthorized}
        {:terminal, _} -> {:error, :unavailable}
      end
    end
  end

  def test_map_matching(%Scope{} = scope, opts \\ []) do
    with {:ok, _scope} <- Access.admit(scope, :admin, admit_opts(opts, write: true)) do
      url = Dawarich.Experimental.value(:atlas_url, repo(opts), env(opts))

      case Dawarich.MapMatching.Atlas.ConnectionTest.call(url) do
        {:ok, %{version: version, revision: revision}} ->
          {:notice, "admin.settings.test_map_matching.success",
           %{"version" => version <> if(revision, do: " (" <> revision <> ")", else: "")}}

        {:error, "not_configured"} ->
          {:alert, "admin.settings.test_map_matching.not_configured", %{}}

        {:error, code} ->
          {:alert, "admin.settings.test_map_matching.failure", %{"error" => code}}
      end
    end
  end

  defp saved({:ok, []}), do: {:ok, :saved}
  defp saved({:ok, refused}), do: {:ok, {:pinned, refused}}
  defp saved({:invalid, message}), do: {:error, {:invalid, message}}
  defp saved({:handoff, :oidc}), do: {:error, :oidc}
  defp saved({:handoff, :encryption}), do: {:error, :encryption}
  defp saved({:handoff, _}), do: {:error, :unauthorized}
  defp saved({:terminal, _}), do: {:error, :unavailable}

  defp health(opts) do
    health =
      Keyword.get_lazy(opts, :health, fn ->
        JobHealth.load(repo(opts), Dawarich.Jobs.repo(), System.get_env("DAWARICH_PHOENIX_NODE"))
      end)

    if is_map(health) and Map.has_key?(health, "summary"),
      do: %{summary: health["summary"], gauges: health["gauges"]},
      else: health
  end

  defp context(scope, opts) do
    %{
      self_hosted: true,
      oidc: false,
      locale: scope.locale,
      repo: repo(opts),
      env: env(opts)
    }
    |> put_opt(opts, :command)
    |> put_opt(opts, :clock)
  end

  defp put_opt(context, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Map.put(context, key, value)
      :error -> context
    end
  end

  defp admit_opts(opts, extra \\ []), do: [env: env(opts)] ++ extra
  defp repo(opts), do: Keyword.get(opts, :repo, Dawarich.Repo)
  defp env(opts), do: Keyword.get(opts, :env, System.get_env())
  defp map(value) when is_map(value), do: value
  defp map(_), do: %{}
end
