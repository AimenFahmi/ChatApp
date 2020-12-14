defmodule Chat.Server do
  require Logger

  def accept(port) do
    {:ok, socket} =
      :gen_tcp.listen(
        port,
        [:binary, packet: :line, active: false, reuseaddr: true]
      )

    # {:ok, my_port} = :inet.port(socket)
    Logger.info("Accepting connections on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.Supervisor.start_child(Chat.Server.TaskSupervisor, fn -> serve(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(socket) do
    logged_in? = is_logged_in?(socket)

    msg =
      with {:ok, data} <- read_line(socket),
           {:ok, command} <- Chat.Server.Command.parse(data),
           true <- logged_in? || (!logged_in? && elem(command, 0) == :login),
           do: Chat.Server.Command.run(socket, command)

    if msg == false do
      write_line(socket, {:ok, "You are not logged in\r\n"})
    else
      write_line(socket, msg)
    end

    serve(socket)
  end

  defp read_line(socket) do
    :gen_tcp.recv(socket, 0)
  end

  def write_line(_socket, {:ok, text, members}) do
    Chat.Server.Router.broadcast(members, text)
  end

  def write_line(socket, {:ok, text}) do
    :gen_tcp.send(socket, text)
  end

  def write_line(socket, {:error, :unknown_command}) do
    :gen_tcp.send(socket, "Unknown command !\r\n")
  end

  def write_line(_socket, {:error, :closed}) do
    exit(:shutdown)
  end

  def write_line(socket, {:error, error}) do
    :gen_tcp.send(socket, "ERROR\r\n")
    exit(error)
  end

  defp is_logged_in?(socket) do
    Chat.get_user_by_socket(socket) != nil
  end
end
