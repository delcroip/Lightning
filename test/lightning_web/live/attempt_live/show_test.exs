defmodule LightningWeb.AttemptLive.ShowTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.WorkOrders
  alias Phoenix.LiveView.AsyncResult

  describe "handle_async/3" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "with exit error", %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:simple_workflow, project: project)

      # Post to webhook
      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{attempts: [%{id: attempt_id}]} =
        WorkOrders.get(wo_id, include: [:attempts])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/attempts/#{attempt_id}")

      %{socket: socket} = :sys.get_state(view.pid)
      initial_async = AsyncResult.loading()
      expected_async = AsyncResult.failed(initial_async, {:exit, "some reason"})

      assert {:noreply, %{assigns: %{log_lines: ^expected_async}}} =
               LightningWeb.AttemptLive.Show.handle_async(
                 :log_lines,
                 {:exit, "some reason"},
                 Map.merge(socket, %{
                   assigns: Map.put(socket.assigns, :log_lines, initial_async)
                 })
               )
    end

    test "lifecycle of an attempt", %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}], jobs: [job]} =
        insert(:simple_workflow, project: project)

      # Post to webhook
      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      workorder =
        %{attempts: [%{id: attempt_id} = attempt]} =
        WorkOrders.get(wo_id, include: [:attempts])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/attempts/#{attempt_id}")

      assert view
             |> element("#attempt-detail-#{attempt_id}")
             |> render_async() =~ "Pending",
             "has pending state"

      assert view
             |> element("#attempt-log-#{attempt_id} > :last-child")
             |> render_async() =~ "Nothing yet...",
             "has no logs"

      refute view
             |> has_element?("#step-list-#{attempt_id} > *"),
             "has no runs"

      attempt =
        Lightning.Repo.update!(
          attempt
          |> Ecto.Changeset.change(%{
            state: :claimed,
            claimed_at: DateTime.utc_now()
          })
        )

      Lightning.Attempts.start_attempt(attempt)

      assert view
             |> element("#attempt-detail-#{attempt_id}")
             |> render_async() =~ "Running",
             "has running state"

      refute view
             |> has_element?("#step-list-#{attempt_id} > *"),
             "has no runs"

      {:ok, run} =
        Lightning.Attempts.start_run(%{
          attempt_id: attempt_id,
          run_id: Ecto.UUID.generate(),
          job_id: job.id,
          input_dataclip_id: workorder.dataclip_id
        })

      html =
        view
        |> element("#step-list-#{attempt_id} > [data-run-id='#{run.id}']")
        |> render_async()

      {:ok, _log_line} =
        Lightning.Attempts.append_attempt_log(attempt, %{
          message: ["I'm the worker, I'm working!"],
          timestamp: DateTime.utc_now()
        })

      assert html =~ job.name
      assert html =~ "Running"

      {:ok, log_line} =
        Lightning.Attempts.append_attempt_log(attempt, %{
          run_id: run.id,
          message: %{message: "hello"},
          timestamp: DateTime.utc_now()
        })

      assert view
             |> element("#attempt-log-#{attempt_id} > *:nth-child(2)")
             |> render_async() =~
               "I'm the worker, I'm working!"
               |> Phoenix.HTML.Safe.to_iodata()
               |> to_string()

      assert view
             |> element("#attempt-log-#{attempt_id} > *:nth-child(3)")
             |> render_async() =~
               log_line.message |> Phoenix.HTML.Safe.to_iodata() |> to_string()

      # Select a run
      view
      |> element("#step-list-#{attempt_id} a[data-phx-link]", job.name)
      |> render_click()

      # Check that the input dataclip is rendered
      assert view
             |> element("#run-input-#{run.id}")
             |> render_async()
             |> Floki.parse_fragment!()
             |> Floki.text() =~ ~s({  "x": 1})

      # Check that the output dataclip isn't available yet.
      # Ensure that "Nothing yet..." is the _last_ bit of text in the output.
      assert view
             |> element("#run-output-#{run.id}")
             |> render_async()
             |> Floki.parse_fragment!()
             |> Floki.text() =~ ~r/Nothing yet\.\.\.\n  $/

      # Complete the run
      {:ok, _run} =
        Lightning.Attempts.complete_run(%{
          attempt_id: attempt_id,
          project_id: project.id,
          run_id: run.id,
          output_dataclip: ~s({"y": 2}),
          output_dataclip_id: Ecto.UUID.generate(),
          reason: "success"
        })

      assert view
             |> element("#run-output-#{run.id}")
             |> render_async()
             |> Floki.parse_fragment!()
             |> Floki.text() =~ ~r/{  "y": 2}/

      {:ok, _} = Lightning.Attempts.complete_attempt(attempt, %{state: :failed})

      assert view
             |> element("#attempt-detail-#{attempt_id}")
             |> render_async() =~ "Failed"
    end
  end
end
