defmodule WebSocketHandler do
  @moduledoc false
  @behaviour WebSock
  require Logger

  @impl true
  def init(_args) do
    # [{:mimetype, mimetype}] = :ets.lookup(:dash, :mimetype)
    dash_path = "priv/dash"
    {:ok, pid_watcher} = GenServer.start(FileWatcher, [self(), dash_path])
    # {:ok, pid_build} = FFmpegProcessor.start(dash_path, mimetype)

    state = %{
      pid_watcher: pid_watcher,
      pid_build: nil,
      init: true,
      dash_path: dash_path
    }

    {:ok, state}
  end

  @impl true
  def handle_in({"stop", [opcode: :text]}, state) do
    Logger.warning("STOPPED------")
    :ok = gracefully_stop(state.pid_build)
    :ok = GenServer.stop(state.pid_watcher)
    {:stop, :normal, state}
  end

  # we receive the binary data from the browser
  def handle_in({msg, [opcode: :binary]}, state) do
    Logger.debug("received data ---------------")

    %{pid_build: pid_build} = state

    # Write the received binary data to the FFmpeg capture process
    :ok = ExCmd.Process.write(pid_build, msg)

    {:ok, state}
  end

  def handle_in({msg, [opcode: :text]}, state) do
    case Jason.decode(msg) do
      {:ok, %{"mimetype" => mimetype}} -> 
        Logger.warning("MIMETYPE: #{mimetype}")
        {:ok, pid_build} = FFmpegProcessor.start(state.dash_path, mimetype)
        {:ok, %{state | pid_build: pid_build}}
      {:error, msg} -> 
        Logger.warning("ERROR: #{inspect(msg)}")
        {:stop, :shutdown, state}
    end
  end

  @impl true

  # file_watcher: the first time the playlist file is created, we send a message to the browser
  def handle_info(:playlist_created, %{init: true} = state) do
    Logger.warning("PLAYLIST CREATED")
    {:push, {:text, "playlist_ready"}, %{state | init: false}}
  end

  # if any other message is received, log it
  def handle_info(msg, state) do
    Logger.warning("UNHANDLED: #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    IO.puts("TERMINATED: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  defp gracefully_stop(pid) do
    if is_pid(pid) && Process.alive?(pid) do
      :ok = ExCmd.Process.close_stdin(pid)
      ExCmd.Process.await_exit(pid, 1_000)
      ExCmd.Process.stop(pid)
    end

    :ok
  end
end
