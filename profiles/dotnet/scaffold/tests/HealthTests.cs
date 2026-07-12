using App;
using Xunit;

public class HealthTests
{
    [Fact]
    public void Status_ReportsOk()
    {
        Assert.Equal("ok", Health.Status()["status"]);
    }
}
