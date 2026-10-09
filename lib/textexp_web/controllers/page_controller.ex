defmodule TextexpWeb.PageController do
  use TextexpWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/documents")
  end
end
