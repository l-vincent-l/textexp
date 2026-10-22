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
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/documents/#{Ash.UUID.generate()}")
  end

  describe "signed in" do
    setup %{conn: conn} do
      user = register_user()
      %{conn: log_in(conn, user), user: user}
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

      assert Document.get_document!(document.id, authorize?: false).title == "Mon document"
      assert has_element?(view, "#documents-#{document.id}", "Mon document")
    end

    test "shows content updates of the open document", %{conn: conn, user: user} do
      document = Document.create_document!(%{}, actor: user)
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
      document = Document.create_document!(%{}, actor: user)
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
      document = Document.create_document!(%{}, actor: user)
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
      document = Document.create_document!(%{}, actor: user)
      other = register_user()
      Document.set_document_members!(document, [%{id: other.id, role: :viewer}], actor: user)

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
      document = Document.create_document!(%{}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.documents_topic(),
        {:document_deleted, document.id}
      )

      assert_redirect(view, ~p"/documents")
    end

    test "a deleted empty document leaves the sidebar", %{conn: conn, user: user} do
      document = Document.create_document!(%{title: "Notes"}, actor: user)
      other = Document.create_document!(%{}, actor: user)
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
      document = Document.create_document!(%{title: "Notes"}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      view |> element("#new-document") |> render_click()
      assert "/documents/" <> id = assert_patch(view)

      assert has_element?(view, "#document-editor-#{id}")
      assert has_element?(view, "#documents-#{id} a.menu-active")
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

    test "another user's document redirects to the list", %{conn: conn} do
      document = Document.create_document!(%{title: "Notes"}, actor: register_user())

      assert {:error, {:live_redirect, %{to: "/documents"}}} =
               live(conn, ~p"/documents/#{document.id}")
    end

    test "an editor renames the document", %{conn: conn, user: user} do
      owner = register_user()
      document = Document.create_document!(%{title: "Notes"}, actor: owner)
      Document.set_document_members!(document, [%{id: user.id, role: :editor}], actor: owner)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(view, "#document-editor-#{document.id}[data-editable='true']")
      view |> element("#title-form") |> render_change(%{"title" => "Mon document"})

      assert Document.get_document!(document.id, authorize?: false).title == "Mon document"
    end

    test "a viewer reads the document without editing it", %{conn: conn, user: user} do
      owner = register_user()
      document = Document.create_document!(%{title: "Notes"}, actor: owner)
      Document.set_document_members!(document, [%{id: user.id, role: :viewer}], actor: owner)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(view, "#document-title[readonly]")
      assert has_element?(view, "#document-editor-#{document.id}[data-editable='false']")

      view |> element("#title-form") |> render_change(%{"title" => "Mon document"})
      assert Document.get_document!(document.id, authorize?: false).title == "Notes"
    end
  end

  describe "sharing" do
    setup %{conn: conn} do
      owner = register_user()
      document = Document.create_document!(%{title: "Notes"}, actor: owner)
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

      assert {:ok, document} = Document.get_document(document.id, actor: editor)
      assert Ash.can?({document, :rename}, editor)
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
      membership = Document.share_document!(document.id, viewer.email, :viewer, actor: owner)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      view |> element("#share-button") |> render_click()
      assert has_element?(view, "#members-#{membership.id}", "Lecteur")

      view |> element("#remove-#{membership.id}") |> render_click()

      refute has_element?(view, "#members-#{membership.id}")
      assert {:error, _} = Document.get_document(document.id, actor: viewer)
    end

    test "members do not see the share button", %{owner: owner, document: document} do
      editor = register_user()
      Document.share_document!(document.id, editor.email, :editor, actor: owner)
      {:ok, view, _html} = live(log_in(build_conn(), editor), ~p"/documents/#{document.id}")

      refute has_element?(view, "#share-button")
    end
  end
end
