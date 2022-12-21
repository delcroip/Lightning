defmodule LightningWeb.DataclipLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.InvocationFixtures

  @create_attrs %{body: "{}", type: :http_request}
  @update_attrs %{body: "{}", type: :global}
  @invalid_attrs %{body: nil, type: :global}

  defp create_dataclip(%{project: project}) do
    dataclip = dataclip_fixture(project_id: project.id)
    %{dataclip: dataclip}
  end

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    setup [:create_dataclip]

    test "no access to project on index", %{conn: conn} do
      project = Lightning.ProjectsFixtures.project_fixture()

      error =
        live(conn, Routes.project_dataclip_index_path(conn, :index, project.id))

      assert error ==
               {:error, {:redirect, %{flash: %{"nav" => :no_access}, to: "/"}}}
    end

    test "lists all dataclips", %{
      conn: conn,
      project: project,
      dataclip: dataclip
    } do
      other_dataclip = dataclip_fixture()

      {:ok, view, html} =
        live(conn, Routes.project_dataclip_index_path(conn, :index, project.id))

      assert html =~ "Dataclips"

      table = view |> element("section#inner_content") |> render()
      assert table =~ "dataclip-#{dataclip.id}"
      refute table =~ "dataclip-#{other_dataclip.id}"
    end

    test "saves new dataclip", %{conn: conn, project: project} do
      {:ok, index_live, _html} =
        live(conn, Routes.project_dataclip_index_path(conn, :index, project.id))

      {:ok, edit_live, _html} =
        index_live
        |> element("a", "New Dataclip")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_dataclip_edit_path(conn, :new, project.id)
        )

      assert page_title(edit_live) =~ "New Dataclip"
      assert render(edit_live) =~ "Save"

      assert edit_live
             |> form("#dataclip-form", dataclip: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        edit_live
        |> form("#dataclip-form", dataclip: @create_attrs)
        |> render_submit()
        |> follow_redirect(
          conn,
          Routes.project_dataclip_index_path(conn, :index, project.id)
        )

      assert html =~ "Dataclip created successfully"
    end

    test "updates dataclip in listing", %{
      conn: conn,
      dataclip: dataclip,
      project: project
    } do
      {:ok, edit_live, _html} =
        live(
          conn,
          Routes.project_dataclip_edit_path(conn, :edit, project.id, dataclip)
        )

      assert edit_live
             |> form("#dataclip-form", dataclip: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        edit_live
        |> form("#dataclip-form", dataclip: @update_attrs)
        |> render_submit()
        |> follow_redirect(
          conn,
          Routes.project_dataclip_index_path(conn, :index, project.id)
        )

      assert html =~ "Dataclip updated successfully"
    end

    test "deletes dataclip in listing", %{
      conn: conn,
      dataclip: dataclip,
      project: project
    } do
      {:ok, index_live, _html} =
        live(conn, Routes.project_dataclip_index_path(conn, :index, project.id))

      assert index_live
             |> element("#dataclip-#{dataclip.id} a[phx-click=delete]")
             |> render_click()

      # We don't delete dataclips yet, we just nil the body column
      assert has_element?(index_live, "#dataclip-#{dataclip.id}")
    end
  end

  describe "Edit" do
    setup [:create_dataclip]

    test "no access to project on edit", %{
      conn: conn,
      dataclip: dataclip,
      project: project_scoped
    } do
      {:ok, _view, html} =
        live(
          conn,
          Routes.project_dataclip_edit_path(
            conn,
            :edit,
            project_scoped.id,
            dataclip.id
          )
        )

      assert html =~ dataclip.id

      project_unscoped = Lightning.ProjectsFixtures.project_fixture()

      error =
        live(
          conn,
          Routes.project_dataclip_edit_path(
            conn,
            :edit,
            project_unscoped.id,
            dataclip.id
          )
        )

      assert error ==
               {:error, {:redirect, %{flash: %{"nav" => :no_access}, to: "/"}}}
    end
  end
end
