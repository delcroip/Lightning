defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  import Ecto.Changeset, only: [get_change: 2]
  alias Lightning.Invocation
  alias Lightning.Invocation.Run
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.WorkOrders
  alias Lightning.WorkOrders.Events
  alias Lightning.WorkOrders.SearchParams
  alias LightningWeb.RunLive.Components

  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.AsyncResult

  @filters_types %{
    search_term: :string,
    body: :boolean,
    log: :boolean,
    workflow_id: :string,
    date_after: :utc_datetime,
    date_before: :utc_datetime,
    wo_date_after: :utc_datetime,
    wo_date_before: :utc_datetime,
    pending: :boolean,
    running: :boolean,
    success: :boolean,
    failed: :boolean,
    crashed: :boolean,
    cancelled: :boolean,
    killed: :boolean,
    exception: :boolean,
    lost: :boolean
  }

  @empty_page %{
    entries: [],
    page_size: 0,
    total_entries: 0,
    page_number: 1,
    total_pages: 0
  }

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(
        params,
        _session,
        %{assigns: %{current_user: current_user, project: project}} = socket
      ) do
    WorkOrders.subscribe(project.id)

    workflows =
      Lightning.Workflows.get_workflows_for(project)
      |> Enum.map(&{&1.name || "Untitled", &1.id})

    can_rerun_job =
      ProjectUsers
      |> Permissions.can?(
        :rerun_job,
        current_user,
        project
      )

    statuses = [
      %{id: :pending, label: "Pending", value: true},
      %{id: :running, label: "Running", value: true},
      %{id: :success, label: "Success", value: true},
      %{id: :failed, label: "Failed", value: true},
      %{id: :crashed, label: "Crashed", value: true},
      %{id: :cancelled, label: "Cancelled", value: true},
      %{id: :killed, label: "Killed", value: true},
      %{id: :exception, label: "Exception", value: true},
      %{id: :lost, label: "Lost", value: true}
    ]

    search_fields = [
      %{id: :body, label: "Input", value: true},
      %{id: :log, label: "Logs", value: true}
    ]

    params = Map.put_new(params, "filters", init_filters())

    {:ok,
     socket
     |> assign(
       workflows: workflows,
       statuses: statuses,
       search_fields: search_fields,
       active_menu_item: :runs,
       work_orders: [],
       selected_work_orders: [],
       can_rerun_job: can_rerun_job,
       pagination_path: &pagination_path(socket, project, &1),
       filters: params["filters"]
     )}
  end

  defp init_filters(),
    do: %{
      "workflow_id" => "",
      "search_term" => "",
      "body" => "true",
      "log" => "true",
      "date_after" =>
        Timex.now() |> Timex.shift(days: -30) |> DateTime.to_string(),
      "date_before" => "",
      "wo_date_after" => "",
      "wo_date_before" => "",
      "pending" => "true",
      "running" => "true",
      "success" => "true",
      "failed" => "true",
      "crashed" => "true",
      "cancelled" => "true",
      "killed" => "true",
      "exception" => "true",
      "lost" => "true"
    }

  @impl true
  def handle_params(params, _url, socket) do
    %{filters: filters, project: project} = socket.assigns

    {:noreply,
     socket
     |> assign(
       page_title: "History",
       run: %Run{},
       filters_changeset: filters_changeset(filters),
       pagination_path: &pagination_path(socket, project, &1, filters),
       page: @empty_page,
       async_page: AsyncResult.loading()
     )
     |> start_async(:load_workorders, fn ->
       monitored_search(project, params)
     end)}
  end

  # returns the search result
  defp monitored_search(project, page_params) do
    span_metadata = %{
      project_id: project.id,
      provided_filters: Map.get(page_params, "filters", %{})
    }

    :telemetry.span(
      [:lightning, :ui, :projects, :history],
      span_metadata,
      fn ->
        search_params =
          Map.get(page_params, "filters", init_filters())
          |> SearchParams.new()

        search_result =
          Invocation.search_workorders(
            project,
            search_params,
            page_params
          )

        {search_result, span_metadata}
      end
    )
  end

  def handle_async(:load_workorders, {:ok, searched_page}, socket) do
    %{async_page: async_page} = socket.assigns

    {:noreply,
     socket
     |> assign(
       page: searched_page,
       async_page: AsyncResult.ok(async_page, searched_page)
     )}
  end

  def handle_async(:load_workorders, {:exit, reason}, socket) do
    %{async_page: async_page} = socket.assigns

    {:noreply,
     socket
     |> assign(
       page: @empty_page,
       async_page: AsyncResult.failed(async_page, {:exit, reason})
     )}
  end

  def checked(changeset, id) do
    case Ecto.Changeset.fetch_field(changeset, id) do
      value when value in [:error, {:changes, true}] -> true
      _ -> false
    end
  end

  defp filters_changeset(params),
    do:
      Ecto.Changeset.cast(
        {%{}, @filters_types},
        params,
        Map.keys(@filters_types)
      )

  @impl true
  def handle_info(%mod{attempt: attempt}, socket)
      when mod in [Events.AttemptCreated, Events.AttemptUpdated] do
    %{work_order: work_order} =
      Lightning.Repo.preload(
        attempt,
        [work_order: [:workflow, attempts: [runs: :job]]],
        force: true
      )

    {:noreply, update_page(socket, work_order)}
  end

  @impl true
  def handle_info(
        %Events.WorkOrderCreated{work_order: work_order},
        socket
      ) do
    %{project: project, filters: filters} = socket.assigns

    filters = Map.merge(filters, %{"workorder_id" => work_order.id})

    {:noreply,
     push_patch(socket,
       to: ~p"/projects/#{project.id}/runs?#{%{filters: filters}}"
     )}
  end

  @impl true
  def handle_info(
        %Events.WorkOrderUpdated{work_order: work_order},
        socket
      ) do
    work_order =
      Lightning.Repo.preload(work_order, [:workflow, attempts: [runs: :job]],
        force: true
      )

    {:noreply, update_page(socket, work_order)}
  end

  @impl true
  def handle_event(
        "rerun",
        %{"attempt_id" => attempt_id, "run_id" => run_id},
        socket
      ) do
    if socket.assigns.can_rerun_job do
      WorkOrders.retry(attempt_id, run_id,
        created_by: socket.assigns.current_user
      )

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  def handle_event("bulk-rerun", attrs, socket) do
    with true <- socket.assigns.can_rerun_job,
         {:ok, count} <- handle_bulk_rerun(socket, attrs) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "New attempt#{if count > 1, do: "s", else: ""} enqueued for #{count} workorder#{if count > 1, do: "s", else: ""}"
       )
       |> push_navigate(
         to:
           ~p"/projects/#{socket.assigns.project.id}/runs?#{%{filters: socket.assigns.filters}}"
       )}
    else
      false ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")}

      {:ok, %{reasons: {0, []}}} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Oops! The chosen step hasn't been run in the latest attempts of any of the selected workorders"
         )}

      {:error, _changes} ->
        {:noreply,
         socket
         |> put_flash(:error, "Oops! an error occured during retries.")}
    end
  end

  def handle_event(
        "toggle_selection",
        %{
          "workorder_id" => workorder_id,
          "selected" => selected?
        },
        %{assigns: assigns} = socket
      ) do
    selected? = String.to_existing_atom(selected?)

    work_orders =
      if selected? do
        workorder =
          Enum.find(assigns.page.entries, fn wo ->
            wo.id == workorder_id
          end)

        selected_workorder = %Lightning.WorkOrder{
          id: workorder.id,
          workflow_id: workorder.workflow_id
        }

        [selected_workorder | assigns.selected_work_orders]
      else
        {_wo, rest} =
          Enum.split_with(assigns.selected_work_orders, fn wo ->
            wo.id == workorder_id
          end)

        rest
      end

    {:noreply, assign(socket, selected_work_orders: work_orders)}
  end

  def handle_event(
        "toggle_all_selections",
        %{"all_selections" => selection},
        %{assigns: %{page: page}} = socket
      ) do
    selection = String.to_existing_atom(selection)

    work_orders =
      if selection do
        Enum.map(page.entries, fn entry ->
          %Lightning.WorkOrder{id: entry.id, workflow_id: entry.workflow_id}
        end)
      else
        []
      end

    {:noreply, assign(socket, selected_work_orders: work_orders)}
  end

  def handle_event("apply_filters", %{"filters" => new_filters}, socket) do
    %{filters: prev_filters, project: project} = socket.assigns
    filters = Map.merge(prev_filters, new_filters)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> push_patch(to: ~p"/projects/#{project.id}/runs?#{%{filters: filters}}")}
  end

  defp find_workflow_name(workflows, workflow_id) do
    Enum.find_value(workflows, fn {name, id} ->
      if id == workflow_id do
        name
      end
    end)
  end

  defp handle_bulk_rerun(socket, %{"type" => "selected", "job" => job_id}) do
    socket.assigns.selected_work_orders
    |> WorkOrders.retry_many(job_id, created_by: socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "all", "job" => job_id}) do
    filter = SearchParams.new(socket.assigns.filters)

    socket.assigns.project
    |> Invocation.search_workorders_query(filter)
    |> Lightning.Repo.all()
    |> WorkOrders.retry_many(job_id, created_by: socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "selected"}) do
    socket.assigns.selected_work_orders
    |> WorkOrders.retry_many(created_by: socket.assigns.current_user)
  end

  defp handle_bulk_rerun(socket, %{"type" => "all"}) do
    filter = SearchParams.new(socket.assigns.filters)

    socket.assigns.project
    |> Invocation.search_workorders_query(filter)
    |> Lightning.Repo.all()
    |> WorkOrders.retry_many(created_by: socket.assigns.current_user)
  end

  defp all_selected?(work_orders, entries) do
    Enum.count(work_orders) == Enum.count(entries)
  end

  defp partially_selected?(work_orders, entries) do
    entries != [] && !none_selected?(work_orders) &&
      !all_selected?(work_orders, entries)
  end

  defp none_selected?(selected_orders) do
    selected_orders == []
  end

  defp selected_workflow_count(selected_orders) do
    selected_orders
    |> Enum.map(fn workorder -> workorder.workflow_id end)
    |> Enum.uniq()
    |> Enum.count()
  end

  defp selected_workorder_count(selected_orders) do
    Enum.count(selected_orders)
  end

  defp maybe_humanize_date(date) do
    date && Timex.format!(date, "{D}/{M}/{YY}")
  end

  defp update_page(socket, workorder) do
    %{page: page, async_page: async_page} = socket.assigns

    updated_page = %{page | entries: update_workorder(page.entries, workorder)}

    assign(socket,
      async_page: AsyncResult.ok(async_page, updated_page),
      page: updated_page
    )
  end

  defp update_workorder(entries, workorder) do
    entries
    |> Enum.reduce([], fn entry, acc ->
      if entry.id == workorder.id do
        [workorder | acc]
      else
        [entry | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp pagination_path(socket, project, route_params, filters \\ %{}) do
    Routes.project_run_index_path(
      socket,
      :index,
      project,
      Keyword.merge(route_params, filters: filters)
    )
  end
end
