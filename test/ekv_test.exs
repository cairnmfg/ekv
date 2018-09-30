defmodule EkvTest do
  use ExUnit.Case

  @key "network_name"
  @value "october17"

  describe "without persistence" do
    setup do
      {:ok, _pid} = InMemory.start_link()
      InMemory.reset()
      on_exit(fn -> InMemory.reset() end)
    end

    test "__ekv__/1 returns path configuration" do
      assert is_nil(InMemory.__ekv__(:path))
    end

    test "__ekv__/1 returns table_name configuration" do
      assert InMemory.__ekv__(:table_name) == :in_memory
    end

    test "__ekv__/1 returns error for unsupported configuration" do
      :error = InMemory.__ekv__(:else)
    end

    test "delete/1 deletes record by key" do
      fixture(InMemory)
      :ok = InMemory.delete(@key)
      {:error, :not_found} = InMemory.read(@key)
    end

    test "delete/1 returns an :ok when record is mising" do
      :ok = InMemory.delete("123456")
    end

    test "read/1 returns the record by key" do
      fixture(InMemory)
      {:ok, returned} = InMemory.read(@key)
      assert returned == @value
    end

    test "read/1 returns the record for an atom key" do
      fixture(InMemory)

      {:ok, returned} =
        @key
        |> String.to_atom()
        |> InMemory.read()

      assert returned == @value
    end

    test "read/1 returns an error tuple when record is mising" do
      {:error, :not_found} = InMemory.read("123")
    end

    test "reset/0 deletes all records" do
      fixture(InMemory)
      {:ok, _returned} = InMemory.read(@key)
      :ok = InMemory.reset()
      {:error, :not_found} = InMemory.read(@key)
    end

    test "write/2 with valid data creates a record" do
      {:error, :not_found} = InMemory.read(@key)
      {:ok, attribute} = InMemory.write(@key, @value)
      assert attribute == @value
      {:ok, returned} = InMemory.read(@key)
      assert returned == @value
    end

    test "write/2 with valid data replaces a record" do
      fixture(InMemory)
      {:ok, attribute} = InMemory.write(@key, "new-value")
      assert attribute == "new-value"
    end

    test "write/2 creates a record for atom keys" do
      {:error, :not_found} = InMemory.read(:datum)
      {:ok, attribute} = InMemory.write(:datum, @value)
      assert attribute == @value
      {:ok, returned} = InMemory.read(:datum)
      assert returned == @value
    end

    test "write/2 returns an error when key is an integer" do
      :error = InMemory.write(123, "new-value")
    end
  end

  describe "with persistence" do
    setup do
      {:ok, _pid} = Persisted.start_link()
      %{path: path} = :sys.get_state(Persisted)
      Persisted.reset()
      File.rm_rf(path)
      on_exit(fn -> Persisted.reset() end)
    end

    test "__ekv__/1 returns path configuration" do
      assert Persisted.__ekv__(:path) == "tmp/persisted"
    end

    test "__ekv__/1 returns table_name configuration" do
      assert Persisted.__ekv__(:table_name) == :persisted
    end

    test "__ekv__/1 returns error for unsupported configuration" do
      :error = Persisted.__ekv__(:else)
    end

    test "read/1 returns record from the file store" do
      %{path: path} = :sys.get_state(Persisted)
      file_path = Path.join(path, "#{@key}.storage")

      File.mkdir_p(path)
      File.write(file_path, :erlang.term_to_binary(@value))

      wait_until(fn ->
        {:ok, returned} = Persisted.read(@key)
        assert returned == @value
      end)
    end

    test "write/2 writes record to file store" do
      %{path: path} = :sys.get_state(Persisted)
      file_path = Path.join(path, "#{@key}.storage")

      {:ok, attribute} = Persisted.write(@key, @value)
      assert attribute == @value

      {:ok, contents} = File.read(file_path)
      assert @value == :erlang.binary_to_term(contents)
    end

    test "delete/1 removes the record from the file store" do
      fixture(Persisted)
      {:ok, _value} = Persisted.read(@key)
      %{path: path} = :sys.get_state(Persisted)
      file_path = Path.join(path, "#{@key}.storage")

      :ok = Persisted.delete(@key)
      {:error, :not_found} = Persisted.read(@key)
      {:error, :enoent} = File.read(file_path)
    end

    test "reset/0 deletes all attributes" do
      fixture(Persisted)
      %{path: path} = :sys.get_state(Persisted)
      file_path = Path.join(path, "#{@key}.storage")

      {:ok, contents} = File.read(file_path)
      assert @value == :erlang.binary_to_term(contents)

      :ok = Persisted.reset()

      wait_until(fn ->
        {:error, :enoent} = File.read(file_path)
      end)
    end
  end

  defp fixture(repo, key \\ @key, value \\ @value) do
    {:ok, attribute} = repo.write(key, value)
    attribute
  end

  defp wait_until(fun), do: wait_until(500, fun)

  defp wait_until(0, fun), do: fun.()

  defp wait_until(timeout, fun) do
    try do
      fun.()
    rescue
      MatchError ->
        :timer.sleep(10)
        wait_until(max(0, timeout - 10), fun)

      ExUnit.AssertionError ->
        :timer.sleep(10)
        wait_until(max(0, timeout - 10), fun)
    end
  end
end
