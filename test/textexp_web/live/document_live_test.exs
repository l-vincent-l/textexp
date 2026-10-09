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
      assert has_element?(view, "#no-document")

      assert {:error, {:redirect, %{to: "/documents/" <> id}}} =
               view |> element("#new-document") |> render_click()

      assert {:ok, _} = Document.get_document(id)
    end

    test "renaming updates the document and the sidebar", %{conn: conn, user: user} do
      document = Document.create_document!(%{}, actor: user)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(view, "#root[data-document-id='#{document.id}']")

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

      # le départ est traité de façon asynchrone par le tracker Presence
      TextexpWeb.Presence.subscribe("viewers:#{document.id}")
      other_id = other.id
      GenServer.stop(other_view.pid)
      assert_receive {TextexpWeb.Presence, {:leave, %{id: ^other_id}}}

      refute has_element?(view, "#viewers-#{other.id}")
    end

    test "an unknown document redirects to the list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/documents"}}} =
               live(conn, ~p"/documents/#{Ash.UUID.generate()}")
    end
  end
end
