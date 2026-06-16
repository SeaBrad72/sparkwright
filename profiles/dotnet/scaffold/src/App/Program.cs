using App;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/healthz", () => Results.Json(Health.Status()));

app.Run();

// Exposed so a WebApplicationFactory-based integration test could boot the host if desired.
public partial class Program { }
