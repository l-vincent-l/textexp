defmodule TextexpWeb.DocumentListLiveTest do
  use TextexpWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Textexp.Document

  # The first search builds the search index in the background, which can take
  # longer than the default 100 ms of render_async/1 on a busy machine.
  @search_timeout 2_000

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
      assert {:ok, _} = Document.get_document(id, authorize?: false)
      assert has_element?(view, "#document-editor-#{id}")
      assert has_element?(view, "#documents-#{id} a.menu-active")
    end

    test "the list has no sidebar and shows each document's title and excerpt",
         %{conn: conn, user: user} do
      document = Document.create_document!(%{title: "Notes"}, actor: user)

      Document.save_snapshot!(document, nil, %{excerpt: "First line\nSecond line"},
        authorize?: false
      )

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
      Document.save_snapshot!(older, nil, %{excerpt: "edited"}, authorize?: false)

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
      render_async(view, @search_timeout)

      assert has_element?(view, "#documents-#{cats.id}")
      refute has_element?(view, "#documents-#{dogs.id}")

      view |> element("#search-form") |> render_change(%{"query" => "chiens"})
      assert has_element?(view, "#documents-#{dogs.id}")
      refute has_element?(view, "#documents-#{cats.id}")

      view |> element("#search-form") |> render_change(%{"query" => ""})
      assert has_element?(view, "#documents-#{cats.id}")
      assert has_element?(view, "#documents-#{dogs.id}")
    end

    test "search results show where the words appear in the body", %{conn: conn, user: user} do
      body = Yex.Doc.new()

      body
      |> Yex.Doc.get_xml_fragment("document-store")
      |> Yex.XmlFragment.push(
        Yex.XmlElementPrelim.new("blockGroup", [
          Yex.XmlElementPrelim.new("blockContainer", [
            Yex.XmlElementPrelim.new("paragraph", [Yex.XmlTextPrelim.from("Le chat dort")])
          ])
        ])
      )

      document =
        %{title: "Notes"}
        |> Document.create_document!(actor: user)
        |> Document.save_snapshot!(Yex.encode_state_as_update!(body), %{excerpt: "Le chat dort"},
          authorize?: false
        )

      {:ok, view, _html} = live(conn, ~p"/documents")
      view |> element("#search-form") |> render_change(%{"query" => "chat"})
      render_async(view, @search_timeout)

      assert has_element?(view, "#documents-#{document.id} p mark", "chat")
    end

    test "lists the documents the user owns or is a member of", %{conn: conn, user: user} do
      other = register_user()
      own = Document.create_document!(%{title: "Mine"}, actor: user)
      shared = Document.create_document!(%{title: "Shared"}, actor: other)
      Document.set_document_members!(shared, [%{id: user.id, role: :viewer}], actor: other)
      hidden = Document.create_document!(%{title: "Hidden"}, actor: other)

      {:ok, view, _html} = live(conn, ~p"/documents")

      assert has_element?(view, "#documents-#{own.id}")
      assert has_element?(view, "#documents-#{shared.id}")
      refute has_element?(view, "#documents-#{hidden.id}")
    end

    test "search ignores the documents the user cannot read", %{conn: conn, user: user} do
      own = Document.create_document!(%{title: "Mes chats"}, actor: user)
      hidden = Document.create_document!(%{title: "Leurs chats"}, actor: register_user())
      {:ok, view, _html} = live(conn, ~p"/documents")

      view |> element("#search-form") |> render_change(%{"query" => "chats"})
      render_async(view, @search_timeout)

      assert has_element?(view, "#documents-#{own.id}")
      refute has_element?(view, "#documents-#{hidden.id}")
    end

    test "a search without match shows that nothing was found", %{conn: conn, user: user} do
      document = Document.create_document!(%{title: "Les chats"}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents")

      view |> element("#search-form") |> render_change(%{"query" => "chats AND ("})
      render_async(view, @search_timeout)

      refute has_element?(view, "#documents-#{document.id}")
      assert has_element?(view, "#documents-empty", "Aucun résultat")
    end
  end

  describe "import" do
    setup %{conn: conn} do
      user = register_user()
      %{conn: log_in(conn, user), user: user}
    end

    # The Yjs state the DocumentImport hook sends for a file holding `text`.
    defp import_state(text) do
      doc = Yex.Doc.new()

      doc
      |> Yex.Doc.get_xml_fragment("document-store")
      |> Yex.XmlFragment.push(
        Yex.XmlElementPrelim.new("blockGroup", [
          Yex.XmlElementPrelim.new("blockContainer", [
            Yex.XmlElementPrelim.new("paragraph", [Yex.XmlTextPrelim.from(text)])
          ])
        ])
      )

      doc |> Yex.encode_state_as_update!() |> Base.encode64()
    end

    test "offers a file input to the hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/documents")

      assert has_element?(
               view,
               "#import-document input#import-files[type=file][phx-hook=DocumentImport]"
             )
    end

    test "creates a document from a converted file", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/documents")

      render_hook(view, "import_document", %{
        "name" => "Recette des crêpes.md",
        "state" => import_state("Farine, œufs, lait")
      })

      assert_reply(view, %{id: id})
      assert has_element?(view, "#documents-#{id}", "Recette des crêpes")
      assert has_element?(view, "#documents-#{id}", "Farine, œufs, lait")

      document = Document.get_document!(id, actor: user)
      assert document.title == "Recette des crêpes"
      assert Document.document_markdown!(document) == "Farine, œufs, lait"
    end

    test "reports a file it could not import", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/documents")

      html = render_hook(view, "import_document", %{"name" => "x.md", "state" => "not base64!"})
      assert_reply(view, %{})
      assert html =~ "Impossible d&#39;importer « x.md »"

      html = render_hook(view, "import_failed", %{"name" => "big.md", "reason" => "too_large"})
      assert html =~ "trop volumineux"
    end
  end
end
