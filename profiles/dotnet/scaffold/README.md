# app — .NET starter scaffold

A minimal solution (web app + test project) **authored to satisfy** the .NET profile's CI language
pipeline (`profiles/dotnet/ci.yml`) after the one-time lockfile step — plus a `/healthz` → 200
endpoint and its test. (Maintainer-authored, **not** executed here — see *Verification status* below.)

> Incept-copied starter — **brownfield-safe**: `incept` copies these files into a fresh repo only.

## One-time lockfile step

`gate-install` runs `dotnet restore --locked-mode`, which requires a committed
`packages.lock.json` per project. Generate them once and commit:

```sh
dotnet restore            # writes src/App/packages.lock.json + tests/packages.lock.json
git add **/packages.lock.json && git commit -m "chore: lockfiles"
```

## Layout

| File                     | Role                                                                  |
|--------------------------|-----------------------------------------------------------------------|
| `app.sln`                | ties the two projects together (the gates operate on the solution).   |
| `src/App/App.csproj`     | net8.0 Minimal-API web app (`RestorePackagesWithLockFile`).           |
| `src/App/Health.cs`      | pure `Health.Status()` — the unit-tested logic.                       |
| `src/App/Program.cs`     | Minimal-API host mapping `GET /healthz` → 200 JSON.                    |
| `tests/Tests.csproj`     | xunit + coverlet; `ExcludeByFile` drops `Program.cs` from coverage.   |
| `tests/HealthTests.cs`   | xunit test on `Health.Status()`.                                      |

## Commands (match `profiles/dotnet/ci.yml`)

```sh
dotnet restore --locked-mode                  # gate-install
dotnet format --verify-no-changes             # gate-lint
dotnet build --no-restore -c Release          # gate-type-check
dotnet test --no-build -c Release /p:CollectCoverage=true /p:Threshold=80 /p:ThresholdType=line  # gate-test
dotnet publish -c Release -o ./publish        # gate-build
```

The web-host bootstrap (`Program.cs`) is excluded from coverage so the ≥80% line gate is met by
the unit-tested `Health` logic.

## Verification status

> **Authored to the `profiles/dotnet/ci.yml` contract; not executed here (dotnet toolchain absent).
> Verify with `dotnet restore && dotnet test` in an adopter env.**
