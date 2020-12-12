defmodule Chat.Server.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
      port = String.to_integer(System.get_env("PORT") || "4040")

      children = [
        {Task.Supervisor, name: Chat.Server.TaskSupervisor},
        Supervisor.child_spec({Task, fn -> Chat.Server.accept(port) end}, restart: :permanent)
      ]

      Supervisor.init(children, strategy: :one_for_one)
  end
end
