defmodule TextexpWeb.SearchLiveTest do
  use TextexpWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Textexp.Document

  defp register_user do
    Textexp.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "search-#{System.unique_integer([:positive])}@example.com",
      password: "a-long-password",
      password_confirmation: "a-long-password"
    })
    |> Ash.create!(authorize?: false)
  end

  setup %{conn: conn} do
    user = register_user()

    conn =
      conn
      |> init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn, user: user}
  end

  test "lists the documents matching the query", %{conn: conn, user: user} do
    cats = Document.create_document!(%{title: "Les chats"}, actor: user)
    dogs = Document.create_document!(%{title: "Les chiens"}, actor: user)

    {:ok, view, _html} = live(conn, ~p"/search")
    # waits for the index to be loaded
    render_async(view)

    view |> element("#search-form") |> render_change(%{"query" => "chats"})

    assert has_element?(view, "#documents-#{cats.id}")
    refute has_element?(view, "#documents-#{dogs.id}")

    view |> element("#search-form") |> render_change(%{"query" => ""})
    refute has_element?(view, "#documents-#{cats.id}")
  end

  test "an invalid query matches nothing", %{conn: conn, user: user} do
    document = Document.create_document!(%{title: "Les chats"}, actor: user)
    {:ok, view, _html} = live(conn, ~p"/search")
    render_async(view)

    view |> element("#search-form") |> render_change(%{"query" => "chats AND ("})

    refute has_element?(view, "#documents-#{document.id}")
  end
end
