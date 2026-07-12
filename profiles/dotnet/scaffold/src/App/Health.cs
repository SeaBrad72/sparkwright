namespace App;

/// <summary>Pure health-check logic — kept free of the web host so it is unit-testable.</summary>
public static class Health
{
    public static IDictionary<string, string> Status() =>
        new Dictionary<string, string> { ["status"] = "ok" };
}
