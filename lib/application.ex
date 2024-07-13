defmodule DashDemo do
  @moduledoc false

  use Application

  def start(_, _) do
   File.mkdir_p("priv/dash")
    webserver = {Bandit, plug: MyWebRouter, port: 4000}
    Supervisor.start_link([webserver], strategy: :one_for_one)
  end
end
