defmodule Ekv do
  @moduledoc """
  Ekv is a simple key-value store providing optional persistence to the local file
  system.

  Under the hood, Ekv uses [ETS](https://erlang.org/doc/man/ets.html) and
  [GenServer](https://hexdocs.pm/elixir/GenServer.html) to plainly manage state.

  ### Usage

  1. Set up a new module to manage the database process with the Ekv macro. Provide
  it a table_name argument.

          defmodule InMemory do
            use Ekv, table_name: :in_memory
          end

  2. Start the process


          $ InMemory.start_link()

  3. Write to, read from, delete from, and reset the store.

      ```
      $ InMemory.read("key")
      {:error, :not_found}

      $ InMemory.write("key", "value")
      {:ok, "value"}

      $ InMemory.read("key")
      {:ok, "value"}

      $ InMemory.delete("key")
      :ok

      $ InMemory.read("key")
      {:error, :not_found}

      $ InMemory.write("key", "value")
      {:ok, "value"}

      $ InMemory.match("ke")
      {:ok, [{"key", "value"}]}

      $ InMemory.reset()
      :ok

      $ InMemory.read("key")
      {:error, :not_found}
      ```

  ### Persistence

  Optionally, provide a path argument to the Ekv macro to persist records to the
  local file system.

  Depending on your use case, this may facilitate retaining some state through
  application restarts.

      defmodule Persisted do
        use Ekv, path: "tmp/persisted", table_name: :persisted
      end
  """

  @extension ".storage"

  @doc false
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      path = Keyword.get(opts, :path)
      table_name = Keyword.get(opts, :table_name, :ekv)

      use GenServer

      @doc false
      def start_link(_opts \\ []) do
        opts = [{:ets_table_name, unquote(table_name)}, {:path, unquote(path)}]
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @doc false
      def init([{:ets_table_name, ets_table_name}, {:path, path}]) do
        :ets.new(ets_table_name, [:named_table, :set, :private])
        {:ok, %{ets_table_name: ets_table_name, path: path}}
      end

      @doc """
      Returns :path and :table_name configuration for module
      using Ekv.
      """
      def __ekv__(:path), do: unquote(path)
      def __ekv__(:table_name), do: unquote(table_name)
      def __ekv__(_key), do: :error

      @doc """
      Delete a record from the key-value store by key.
      """
      def delete(key), do: Ekv.delete(__MODULE__, key)

      @doc """
      Match records in the key-value store.
      """
      def match(pattern), do: Ekv.match(__MODULE__, pattern)

      @doc """
      Read a record from the key-value store by key.
      """
      def read(key), do: Ekv.read(__MODULE__, key)

      @doc """
      Delete all records in the key-value store.
      """
      def reset(), do: Ekv.reset(__MODULE__)

      @doc """
      Write a records in the key-value store by key.
      """
      def write(key, value), do: Ekv.write(__MODULE__, key, value)

      @doc false
      def handle_call(
            {:match, pattern},
            _from,
            %{ets_table_name: ets_table_name, path: path} = state
          ) do
        Ekv.handle(:match, pattern, state)
      end

      @doc false
      def handle_call(
            {:read, key},
            _from,
            %{ets_table_name: ets_table_name, path: path} = state
          ) do
        Ekv.handle(:read, key, state)
      end

      @doc false
      def handle_call(
            {:write, key, value},
            _from,
            %{ets_table_name: ets_table_name, path: path} = state
          ) do
        Ekv.handle(:write, key, value, state)
      end

      @doc false
      def handle_cast(
            {:delete, key},
            %{ets_table_name: ets_table_name, path: path} = state
          ) do
        Ekv.handle(:delete, key, state)
      end

      @doc false
      def handle_cast(
            :reset,
            %{ets_table_name: ets_table_name, path: path} = state
          ) do
        Ekv.handle(:reset, state)
      end
    end
  end

  @doc false
  def delete(module, key) when is_atom(key),
    do: delete(module, Atom.to_string(key))

  def delete(module, key) when is_binary(key),
    do: GenServer.cast(module, {:delete, key})

  def delete(_module, _key), do: :error

  @doc false
  def handle(:delete, key, %{ets_table_name: ets_table_name, path: path} = state) do
    :ets.delete(ets_table_name, key)
    delete_persisted(path, key)
    {:noreply, state}
  end

  def handle(:match, pattern, %{ets_table_name: ets_table_name, path: path} = state)
      when is_nil(path) do
    results =
      :ets.tab2list(ets_table_name)
      |> Enum.filter(fn {key, _value} -> String.contains?(key, pattern) end)

    {:reply, {:ok, results}, state}
  end

  def handle(:match, pattern, %{ets_table_name: ets_table_name, path: path} = state) do
    results =
      "#{path}/*#{pattern}*#{@extension}"
      |> Path.wildcard()
      |> Enum.filter(fn filename -> String.ends_with?(filename, @extension) end)
      |> Enum.map(fn filename ->
        key = Path.basename(filename, @extension)

        case lookup(ets_table_name, key, path, state) do
          {:ok, value} ->
            {key, value}

          _ ->
            :ignore
        end
      end)
      |> Enum.reject(fn result -> result == :ignore end)

    {:reply, {:ok, results}, state}
  end

  def handle(:read, key, %{ets_table_name: ets_table_name, path: path} = state) do
    {:reply, lookup(ets_table_name, key, path, state), state}
  end

  @doc false
  def handle(:reset, %{ets_table_name: ets_table_name, path: path} = state) do
    :ets.delete_all_objects(ets_table_name)
    reset_persisted(path)
    {:noreply, state}
  end

  @doc false
  def handle(:write, key, value, %{ets_table_name: ets_table_name, path: path} = state) do
    if String.contains?(key, "/") do
      {:reply, :error, state}
    else
      true = :ets.insert(ets_table_name, {key, value})
      write_persisted(path, {key, value}, state)
    end
  end

  @doc false
  def match(module, pattern) when is_binary(pattern),
    do: GenServer.call(module, {:match, pattern})

  @doc false
  def read(module, key) when is_atom(key),
    do: read(module, Atom.to_string(key))

  def read(module, key) when is_binary(key),
    do: GenServer.call(module, {:read, key})

  def read(_module, _key), do: :error

  @doc false
  def reset(module), do: GenServer.cast(module, :reset)

  @doc false
  def write(module, key, value) when is_atom(key),
    do: write(module, Atom.to_string(key), value)

  def write(module, key, value) when is_binary(key),
    do: GenServer.call(module, {:write, key, value})

  def write(_module, _key, _value), do: :error

  defp lookup(ets_table_name, key, path, state) do
    case :ets.lookup(ets_table_name, key) do
      [{^key, value}] ->
        {:ok, value}

      _ ->
        read_persisted(path, key, state)
    end
  end

  defp delete_persisted(path, _key) when is_nil(path), do: :ignore

  defp delete_persisted(path, key), do: File.rm(filepath_for(path, key))

  defp filepath_for(dir_path, key), do: Path.join(dir_path, key <> @extension)

  defp read_persisted(path, _key, _state) when is_nil(path),
    do: {:error, :not_found}

  defp read_persisted(path, key, %{ets_table_name: ets_table_name}) do
    case File.read(filepath_for(path, key)) do
      {:ok, contents} when contents != "" ->
        term = :erlang.binary_to_term(contents)
        :ets.insert(ets_table_name, [{key, term}])
        {:ok, term}

      _ ->
        {:error, :not_found}
    end
  end

  defp reset_persisted(path) when is_nil(path), do: :ignore

  defp reset_persisted(path), do: File.rm_rf(path)

  defp write_persisted(path, {_key, value}, state) when is_nil(path),
    do: {:reply, {:ok, value}, state}

  defp write_persisted(path, {key, value}, state) do
    case File.mkdir_p(path) do
      :ok ->
        File.write(filepath_for(path, key), :erlang.term_to_binary(value))
        {:reply, {:ok, value}, state}

      error ->
        {:reply, error, state}
    end
  end
end
