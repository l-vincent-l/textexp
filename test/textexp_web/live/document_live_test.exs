defmodule TextexpWeb.DocumentLiveTest do
  use TextexpWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Textexp.Document

  defp register_user do
    Textexp.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "live-#{System.unique_integer([:positive])}@example.com",
      password: "a-long-password",
      password_confirmation: "a-long-password"
    })
    |> Ash.create!(authorize?: false)
  end

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  test "redirects anonymous visitors to the sign-in page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/documents")
  end

  describe "signed in" do
    setup %{conn: conn} do
      user = register_user()
      %{conn: log_in(conn, user), user: user}
    end

    test "creating a document opens it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/documents")
      assert has_element?(view, "#new-document")

      view |> element("#new-document") |> render_click()
      assert "/documents/" <> id = assert_patch(view)

      assert {:ok, _} = Document.get_document(id)
      assert has_element?(view, "#document-editor-#{id}")
      assert has_element?(view, "#documents-#{id} a.menu-active")
    end

    test "the list has no sidebar and shows each document's title and excerpt",
         %{conn: conn, user: user} do
      document = Document.create_document!(%{title: "Notes"}, actor: user)
      Document.save_snapshot!(document, nil, %{excerpt: "First line\nSecond line"})
      untitled = Document.create_document!(%{}, actor: user)

      {:ok, view, _html} = live(conn, ~p"/documents")

      refute has_element?(view, "#sidebar-drawer")
      assert has_element?(view, "#documents-#{document.id} h2", "Notes")
      assert has_element?(view, "#documents-#{document.id} p", "Second line")
      assert has_element?(view, "#documents-#{document.id} time")
      assert has_element?(view, "#documents-#{untitled.id} h2", "Sans titre")
      refute has_element?(view, "#documents-#{untitled.id} p")
    end

    test "the list is sorted by last update, most recent first", %{conn: conn, user: user} do
      older = Document.create_document!(%{title: "Older"}, actor: user)
      newer = Document.create_document!(%{title: "Newer"}, actor: user)
      # editing the older one makes it the most recent
      Document.save_snapshot!(older, nil, %{excerpt: "edited"})

      {:ok, view, _html} = live(conn, ~p"/documents")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#documents > li[id^='documents-']:not(#documents-empty)")
        |> LazyHTML.attribute("id")

      assert ids == ["documents-#{older.id}", "documents-#{newer.id}"]
    end

    test "renaming updates the document and the sidebar", %{conn: conn, user: user} do
      document = Document.create_document!(%{}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      editor = "#document-editor-#{document.id}[phx-hook='DocumentEditor']"
      assert has_element?(view, "#{editor}[data-document-id='#{document.id}']")
      assert has_element?(view, "#documents-link[href='/documents']")
      assert has_element?(view, "#{editor} [data-skeleton]")
      assert has_element?(view, "#{editor} [data-editor][hidden]")

      view |> element("#title-form") |> render_change(%{"title" => "Mon document"})

      assert Document.get_document!(document.id).title == "Mon document"
      assert has_element?(view, "#documents-#{document.id}", "Mon document")
    end

    test "shows content updates of the open document", %{conn: conn, user: user} do
      document = Document.create_document!(%{}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.topic(document.id),
        {:document_updated, document.id, ~U[2030-01-02 03:04:05.000000Z]}
      )

      assert has_element?(view, "#last-update", "02/01/2030 03:04:05")
    end

    test "lists the people viewing the document", %{conn: conn, user: user} do
      document = Document.create_document!(%{}, actor: user)
      other = register_user()

      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      {:ok, other_view, _html} = live(log_in(build_conn(), other), ~p"/documents/#{document.id}")

      assert has_element?(view, "#viewers-#{user.id}")
      assert has_element?(view, "#viewers-#{other.id}")

      # the leave is handled asynchronously by the Presence tracker
      TextexpWeb.Presence.subscribe("viewers:#{document.id}")
      other_id = other.id
      GenServer.stop(other_view.pid)
      assert_receive {TextexpWeb.Presence, {:leave, %{id: ^other_id}}}

      refute has_element?(view, "#viewers-#{other.id}")
    end

    test "a deleted empty document leaves the sidebar", %{conn: conn, user: user} do
      document = Document.create_document!(%{}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents")
      assert has_element?(view, "#documents-#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.documents_topic(),
        {:document_deleted, document.id}
      )

      refute has_element?(view, "#documents-#{document.id}")
    end

    test "the open document being deleted redirects to the list", %{conn: conn, user: user} do
      document = Document.create_document!(%{}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.documents_topic(),
        {:document_deleted, document.id}
      )

      assert_patch(view, ~p"/documents")
    end

    test "opening a document from the list patches to it with the sidebar",
         %{conn: conn, user: user} do
      document = Document.create_document!(%{title: "Notes"}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents")

      view |> element("#documents-#{document.id} a") |> render_click()
      assert_patch(view, ~p"/documents/#{document.id}")

      assert has_element?(view, "#document-editor-#{document.id}")
      assert has_element?(view, "#documents-#{document.id} a.menu-active", "Notes")
    end

    test "switching documents moves the editor, the active item and the viewer",
         %{conn: conn, user: user} do
      first = Document.create_document!(%{title: "First"}, actor: user)
      second = Document.create_document!(%{title: "Second"}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents/#{first.id}")
      assert [_] = TextexpWeb.Presence.list_users("viewers:#{first.id}")

      view |> element("#documents-#{second.id} a") |> render_click()
      assert_patch(view, ~p"/documents/#{second.id}")

      assert has_element?(view, "#document-editor-#{second.id}")
      refute has_element?(view, "#document-editor-#{first.id}")
      assert has_element?(view, "#documents-#{second.id} a.menu-active")
      refute has_element?(view, "#documents-#{first.id} a.menu-active")
      assert has_element?(view, "#viewers-#{user.id}")
      assert TextexpWeb.Presence.list_users("viewers:#{first.id}") == []
    end

    test "an unknown document redirects to the list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/documents"}}} =
               live(conn, ~p"/documents/#{Ash.UUID.generate()}")
    end
  end
end
