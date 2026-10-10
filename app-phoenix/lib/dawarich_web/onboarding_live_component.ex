defmodule DawarichWeb.OnboardingLiveComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.Onboarding

  @timeout 30_000

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:completed, fn -> false end)
     |> assign_new(:demo_status, fn -> :idle end)
     |> assign_new(:demo_run, fn -> nil end)
     |> assign_new(:demo_loader, fn -> nil end)
     |> assign_new(:demo_timeout, fn -> @timeout end)}
  end

  def handle_event("onboarding:complete", _params, socket) do
    case Onboarding.complete(socket.assigns.scope) do
      :ok -> {:noreply, assign(socket, :completed, true)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("demo:load", _params, %{assigns: %{demo_status: :loading}} = socket),
    do: {:noreply, socket}

  def handle_event("demo:load", _params, socket) do
    run = make_ref()
    %{scope: scope, demo_timeout: timeout} = socket.assigns
    loader = socket.assigns.demo_loader || (&Onboarding.load_demo/1)

    {:noreply,
     socket
     |> assign(demo_status: :loading, demo_run: run)
     |> start_async(:demo_load, fn -> {run, bounded(fn -> loader.(scope) end, timeout)} end)}
  end

  def handle_event("demo:remove", _params, socket) do
    case Onboarding.remove_demo(socket.assigns.scope) do
      {:ok, _} -> {:noreply, push_navigate(socket, to: "/")}
      _ -> {:noreply, assign(socket, :demo_status, :failed)}
    end
  end

  def handle_async(:demo_load, {:ok, {run, result}}, %{assigns: %{demo_run: run}} = socket) do
    case result do
      {:ok, %{landing: landing}} -> {:noreply, push_navigate(socket, to: landing)}
      _ -> {:noreply, assign(socket, demo_status: :failed, demo_run: nil)}
    end
  end

  def handle_async(:demo_load, {:ok, _stale}, socket), do: {:noreply, socket}

  def handle_async(:demo_load, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, demo_status: :failed, demo_run: nil)}

  defp bounded(fun, timeout) do
    task = Task.async(fun)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :timeout}
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        demo: assigns.navbar.imports.demo,
        failure:
          t(assigns.locale, "javascript.messages.failed_to_load_demo_data_please_try_again", %{})
      )

    ~H"""
    <div id={@id}>
      <DawarichWeb.NativeOnboarding.modal
        current_user={@scope.user}
        navbar={@navbar}
        locale={@locale}
        base_url={@base_url}
        rails_csrf_token={@rails_csrf_token}
        auto_open={@auto_open and not @completed}
        target={@myself}
        demo_status={@demo_status}
      />
      <p
        :if={@demo_status == :failed}
        id="native-demo-error"
        class="alert alert-error fixed bottom-4 left-4 right-4 z-[10001]"
        role="alert"
      >
        {@failure}
      </p>
      <DawarichWeb.NativeDemoBanner.banner :if={@demo} locale={@locale} target={@myself} />
    </div>
    """
  end
end
