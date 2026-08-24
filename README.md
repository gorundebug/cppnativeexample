# C++ native example

Direct userver HTTP + gRPC implementation of the example business path,
without ServiceLib. It retains userver as the generated C++ runtime so the
benchmark isolates the ServiceLib pipeline overhead. Items within one order
are processed sequentially.

The Docker build resolves the userver dependency graph with Conan 2 and the
checked-in lockfile for the target platform. Explicit dependency and tool
versions are generated from ServiceGen's canonical `dependencies.yaml`.

```sh
make docker-build
make docker-up
make docker-down
```

Regenerate lockfiles after an intentional dependency update with
`make conan-lock`. Normal builds never mutate them.
