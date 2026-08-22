# C++ native example

Direct userver HTTP + gRPC implementation of the example business path,
without ServiceLib. It retains userver as the generated C++ runtime so the
benchmark isolates the ServiceLib pipeline overhead. Items within one order
are processed sequentially.

```sh
docker compose up --build
```
