using App;

var builder = WebApplication.CreateBuilder(args);

// Neutralize Kestrel's Server header — AppServer stamps a neutral "reference-app"
// (no framework/version leak). No effect under the in-memory TestServer; required
// under Kestrel so the deployed container leaks no framework/version.
builder.WebHost.ConfigureKestrel(options => options.AddServerHeader = false);

var app = builder.Build();

// FLAG_FILE boot gate — install the file-config live provider BEFORE serving, so the
// running host's /greeting reflects live file flips with no restart.
AppServer.ConfigureProvider();

// Terminal handler: routing + security headers + per-request telemetry live in
// AppServer (method-agnostic 404, HEAD semantics) — NOT ASP.NET endpoint routing,
// which would return 405 for a non-GET instead of the contract's hardened JSON 404.
app.Run(AppServer.HandleAsync);

app.Run();

// Exposed so a WebApplicationFactory<Program>-based integration test can boot the host.
public partial class Program { }
