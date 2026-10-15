defmodule TextexpWeb.DocumentListLiveTest do
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
             live(conn, ~p"/documents")
  end

  describe "signed in" do
    setup %{conn: conn} do
      user = register_user()
      %{conn: log_in(conn, user), user: user}
    end

    test "creating a document opens it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/documents")
      assert has_element?(view, "#new-document")

      assert {:error, {:live_redirect, %{to: "/documents/" <> id = path}}} =
               view |> element("#new-document") |> render_click()

      {:ok, view, _html} = live(conn, path)
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

    test "a deleted empty document leaves the list", %{conn: conn, user: user} do
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

    test "opening a document from the list navigates to it with the sidebar",
         %{conn: conn, user: user} do
      document = Document.create_document!(%{title: "Notes"}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents")

      {:ok, view, _html} =
        view
        |> element("#documents-#{document.id} a")
        |> render_click()
        |> follow_redirect(conn, ~p"/documents/#{document.id}")

      assert has_element?(view, "#document-editor-#{document.id}")
      assert has_element?(view, "#documents-#{document.id} a.menu-active", "Notes")
    end

    test "searching lists the matching documents, and clearing it lists all of them",
         %{conn: conn, user: user} do
      cats = Document.create_document!(%{title: "Les chats"}, actor: user)
      dogs = Document.create_document!(%{title: "Les chiens"}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents")

      view |> element("#search-form") |> render_change(%{"query" => "chats"})
      # waits for the index, built for the first search
      render_async(view)

      assert has_element?(view, "#documents-#{cats.id}")
      refute has_element?(view, "#documents-#{dogs.id}")

      view |> element("#search-form") |> render_change(%{"query" => "chiens"})
      assert has_element?(view, "#documents-#{dogs.id}")
      refute has_element?(view, "#documents-#{cats.id}")

      view |> element("#search-form") |> render_change(%{"query" => ""})
      assert has_element?(view, "#documents-#{cats.id}")
      assert has_element?(view, "#documents-#{dogs.id}")
    end

    test "a search without match shows that nothing was found", %{conn: conn, user: user} do
      document = Document.create_document!(%{title: "Les chats"}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents")

      view |> element("#search-form") |> render_change(%{"query" => "chats AND ("})
      render_async(view)

      refute has_element?(view, "#documents-#{document.id}")
      assert has_element?(view, "#documents-empty", "Aucun résultat")
    end
  end
end
