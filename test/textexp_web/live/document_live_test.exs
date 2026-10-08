defmodule TextexpWeb.DocumentLiveTest do
  use TextexpWeb.ConnCase

  import Phoenix.LiveViewTest

  test "redirects anonymous visitors to the sign-in page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/doc")
  end
end
