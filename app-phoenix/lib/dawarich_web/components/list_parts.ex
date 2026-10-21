defmodule DawarichWeb.ListParts do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.ListParams

  @badge "inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium whitespace-nowrap "
  @status_classes %{
    "completed" => "bg-success/10 text-success",
    "processing" => "bg-info/10 text-info",
    "created" => "bg-warning/10 text-warning",
    "failed" => "bg-error/10 text-error",
    "deleting" => "bg-warning/10 text-warning"
  }

  attr :title, :string, required: true
  slot :inner_block

  def page_header(assigns) do
    ~H"""
    <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
      <h1 class="text-3xl font-bold">{@title}</h1>
      <div :if={@inner_block != []} class="flex flex-wrap gap-2">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :column, :string, required: true
  attr :path, :string, required: true
  attr :list, :map, required: true

  def sort_link(assigns) do
    active = assigns.list.current_sort == assigns.column

    {icon_name, icon_class} =
      cond do
        active and assigns.list.direction == :asc -> {"chevron-up", "w-4 h-4 inline-block"}
        active -> {"chevron-down", "w-4 h-4 inline-block"}
        true -> {"arrow-down-up", "w-4 h-4 inline-block opacity-30"}
      end

    assigns =
      assign(assigns,
        active: active,
        href: ListParams.sort_href(assigns.path, assigns.column, assigns.list),
        icon_name: icon_name,
        icon_class: icon_class
      )

    ~H"""
    <.link
      patch={@href}
      class={["inline-flex items-center gap-1 link link-hover", @active && "font-bold"]}
    >{@title}<.icon name={@icon_name} class={@icon_class} /></.link>
    """
  end

  attr :record, :map, required: true
  attr :locale, :string, required: true

  def status_badge(assigns) do
    assigns =
      assign(assigns,
        css:
          @badge <>
            Map.get(@status_classes, assigns.record.status, "bg-base-200 text-base-content/50"),
        label: t(assigns.locale, "statuses." <> assigns.record.status, %{}),
        error: assigns.record.status == "failed" and Ruby.present?(assigns.record.error_message)
      )

    ~H"""
    <span :if={@error} class="inline-flex items-center gap-1 whitespace-nowrap"><span class={@css}>{@label}</span><span
      class="tooltip tooltip-left cursor-help inline-flex items-center"
      data-tip={@record.error_message}
    ><.icon name="circle-alert" class="w-3.5 h-3.5 text-error" /></span></span>
    <span :if={!@error} class={@css}>{@label}</span>
    """
  end
end
