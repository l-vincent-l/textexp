defmodule TextexpWeb.DocumentLiveTest do
  use TextexpWeb.ConnCase

  alias Textexp.Fixtures

  import Phoenix.LiveViewTest

  alias Textexp.Document

  defp register_user, do: Fixtures.confirmed_user()

  defp log_in(conn, user), do: Fixtures.log_in(conn, user)

  describe "signed in" do
    setup %{conn: conn} do
      user = register_user()
      %{conn: log_in(conn, user), user: user}
    end

    test "renaming updates the document and the sidebar", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
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
      document = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.topic(document.id),
        {:document_updated, document.id, ~U[2030-01-02 03:04:05.000000Z], nil}
      )

      assert has_element?(view, "#last-update", "02/01/2030 03:04:05")
    end

    test "shows the title given by a save to an untitled document",
         %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.topic(document.id),
        {:document_updated, document.id, DateTime.utc_now(), "Note du 01-02-2030"}
      )

      assert has_element?(view, "#document-title[value='Note du 01-02-2030']")
      assert has_element?(view, "#documents-#{document.id}", "Note du 01-02-2030")
      assert page_title(view) =~ "Note du 01-02-2030"
    end

    test "a save does not replace the title being typed", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      view |> element("#title-form") |> render_change(%{"title" => "Mon titre"})

      # saved before the title was typed
      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.topic(document.id),
        {:document_updated, document.id, DateTime.utc_now(), "Note du 01-02-2030"}
      )

      assert has_element?(view, "#document-title[value='Mon titre']")
    end

    test "lists the people viewing the document", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      other = register_user()
      Fixtures.share!(user, document, other, :viewer)

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

    test "the open document being deleted redirects to the list", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.documents_topic(),
        {:document_deleted, document.id}
      )

      assert_redirect(view, ~p"/documents")
    end

    test "a deleted empty document leaves the sidebar", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{title: "Notes"})
      other = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      assert has_element?(view, "#documents-#{other.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.documents_topic(),
        {:document_deleted, other.id}
      )

      refute has_element?(view, "#documents-#{other.id}")
    end

    test "creating a document from the sidebar opens it", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{title: "Notes"})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      view |> element("#new-document") |> render_click()
      assert "/documents/" <> id = assert_patch(view)

      assert has_element?(view, "#document-editor-#{id}")
      assert has_element?(view, "#documents-#{id} a.menu-active")
    end

    test "switching documents moves the editor, the active item and the viewer",
         %{conn: conn, user: user} do
      first = Fixtures.create_document!(user, %{title: "First"})
      second = Fixtures.create_document!(user, %{title: "Second"})
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
               live(conn, ~p"/documents/#{Ecto.UUID.generate()}")
    end

    test "another user's document redirects to the list", %{conn: conn} do
      document = Fixtures.create_document!(register_user(), %{title: "Notes"})

      assert {:error, {:live_redirect, %{to: "/documents"}}} =
               live(conn, ~p"/documents/#{document.id}")
    end

    test "an editor renames the document", %{conn: conn, user: user} do
      owner = register_user()
      document = Fixtures.create_document!(owner, %{title: "Notes"})
      Fixtures.share!(owner, document, user, :editor)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(view, "#document-editor-#{document.id}[data-editable='true']")
      view |> element("#title-form") |> render_change(%{"title" => "Mon document"})

      assert Document.get_document!(document.id).title == "Mon document"
    end

    test "a viewer reads the document without editing it", %{conn: conn, user: user} do
      owner = register_user()
      document = Fixtures.create_document!(owner, %{title: "Notes"})
      Fixtures.share!(owner, document, user, :viewer)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(view, "#document-title[readonly]")
      assert has_element?(view, "#document-editor-#{document.id}[data-editable='false']")

      view |> element("#title-form") |> render_change(%{"title" => "Mon document"})
      assert Document.get_document!(document.id).title == "Notes"
    end
  end

  describe "sharing" do
    setup %{conn: conn} do
      owner = register_user()
      document = Fixtures.create_document!(owner, %{title: "Notes"})
      %{conn: log_in(conn, owner), owner: owner, document: document}
    end

    test "the owner invites an address as editor", %{conn: conn, document: document} do
      editor = register_user()
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      refute has_element?(view, "#share-panel")
      view |> element("#share-button") |> render_click()
      assert has_element?(view, "#members-empty")

      view
      |> form("#share-form", share: %{email: editor.email, role: "editor"})
      |> render_submit()

      assert has_element?(view, "#members li", to_string(editor.email))
      assert has_element?(view, "#members li", "Éditeur")

      assert {:ok, %{role: :editor}} = Document.get_document(document.id, editor)
    end

    test "an address without account is refused", %{conn: conn, document: document} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      view |> element("#share-button") |> render_click()

      html =
        view
        |> form("#share-form", share: %{email: "nobody@example.com", role: "viewer"})
        |> render_submit()

      assert html =~ "aucun compte avec cette adresse"
      assert has_element?(view, "#members-empty")
    end

    test "the owner removes a member", %{conn: conn, owner: owner, document: document} do
      viewer = register_user()
      membership = Fixtures.share!(owner, document, viewer, :viewer)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      view |> element("#share-button") |> render_click()
      assert has_element?(view, "#members-#{membership.id}", "Lecteur")

      view |> element("#remove-#{membership.id}") |> render_click()

      refute has_element?(view, "#members-#{membership.id}")
      assert {:error, _} = Document.get_document(document.id, viewer)
    end

    test "a member removed is sent back to the list", %{owner: owner, document: document} do
      viewer = register_user()
      membership = Fixtures.share!(owner, document, viewer, :viewer)
      {:ok, view, _html} = live(log_in(build_conn(), viewer), ~p"/documents/#{document.id}")

      :ok = Document.remove_member(owner, membership.id)

      assert_redirect(view, ~p"/documents")
    end

    test "a member whose role changes gets the page again", %{owner: owner, document: document} do
      member = register_user()
      Fixtures.share!(owner, document, member, :viewer)
      {:ok, view, _html} = live(log_in(build_conn(), member), ~p"/documents/#{document.id}")

      Fixtures.share!(owner, document, member, :editor)

      assert_redirect(view, ~p"/documents/#{document.id}")
    end

    test "members do not see the share button", %{owner: owner, document: document} do
      editor = register_user()
      Fixtures.share!(owner, document, editor, :editor)
      {:ok, view, _html} = live(log_in(build_conn(), editor), ~p"/documents/#{document.id}")

      refute has_element?(view, "#share-button")
    end
  end
end
