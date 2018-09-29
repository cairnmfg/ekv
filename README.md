# Ekv

Ekv is a simple ETS+GenServer key-value store providing optional persistence to the local file system.

[![CircleCI](https://circleci.com/gh/cairnmfg/ekv.svg?style=svg)](https://circleci.com/gh/cairnmfg/ekv)

Ekv was extracted from [cairnmfg/field](https://github.com/cairnmfg/field), an embedded firmware. The local file system persistence in Ekv is designed to simplify the process of maintaining state through system reboots/crashes in embedded systems (or other kinds of lightweight software environments with partial/read-only file systems).

## Usage

1. Set up a new module to manage the database process and provide it a table_name argument.

```
defmodule InMemory do
  use Ekv, table_name: :in_memory
end
```

2. Start the process

```
> InMemory.start_link()
```

3. Write to, read from, delete from, and reset the store.

```
> InMemory.read("key")
{:error, :not_found}

> InMemory.write("key", "value")
{:ok, "value"}

> InMemory.read("key")
{:ok, "value"}

> InMemory.delete("key")
:ok

> InMemory.read("key")
{:error, :not_found}

> InMemory.write("key", "value")
{:ok, "value"}

> InMemory.reset()
:ok

> InMemory.read("key")
{:error, :not_found}
```

## Persistence

Optionally, provide a path argument to the Ekv macro to additionally persist records to the local file system.

Depending on your use case, you may be useful to retain state through application restarts.

```
defmodule Persisted do
  use Ekv, path: "tmp/persisted", table_name: :persisted
end
```
