# syntax=docker/dockerfile:1
# Reference container image for the .NET / ASP.NET Core profile.
# COPY & ADAPT: copy to your project root as `Dockerfile`. INERT here in the kit.
# Satisfies DEVELOPMENT-STANDARDS.md §14 (container image supply-chain):
# multi-stage, non-root, minimal (chiseled) base.

# ---- builder: full .NET SDK, never shipped ----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS builder
WORKDIR /src
# Cache restore: copy the solution/project + lockfile first, restore, then the source.
COPY *.sln packages.lock.json ./
COPY . .
RUN dotnet restore
# ADAPT the project path; publish framework-dependent (the aspnet runtime base supplies it).
RUN dotnet publish -c Release -o /app/publish --no-restore

# ---- runtime: chiseled ASP.NET (ultra-minimal, no shell) ----
FROM mcr.microsoft.com/dotnet/aspnet:8.0-noble-chiseled AS runtime
WORKDIR /app
COPY --from=builder /app/publish .
ENV ASPNETCORE_HTTP_PORTS=8080
# The chiseled image already runs as the non-root 'app' user (APP_UID=1654); we re-declare
# it as a LITERAL because the conformance check rejects a build-time $APP_UID variable
# (a build var can't be statically attested non-root) and to pin parity with k8s runAsUser.
USER 1654
EXPOSE 8080
# No in-image HEALTHCHECK: chiseled has no shell/curl. Health is via the k8s probes below
# (ASP.NET Core health checks mapped to /healthz + /readyz).
# ADAPT `App.dll` to your published entry assembly.
ENTRYPOINT ["dotnet", "App.dll"]
