using Xunit;

namespace App.Tests;

/// <summary>
/// Unit tests for the feature-flag registry + provider seam (env floor).
/// These mutate PROCESS-GLOBAL state (env vars + the active-provider slot), so the
/// flag test classes share one xUnit collection to run serially and never race.
/// </summary>
[Collection("Flags")]
public class FlagsTests
{
    private const string EnvVar = "FEATURE_NEW_GREETING";

    private static void ClearEnv() => Environment.SetEnvironmentVariable(EnvVar, null);

    [Fact]
    public void Default_IsOff_ForKnownFlag()
    {
        ClearEnv();
        Flags.ResetProvider();
        try
        {
            Assert.False(Flags.IsEnabled("new_greeting"));
        }
        finally
        {
            Flags.ResetProvider();
        }
    }

    [Fact]
    public void UnknownFlagName_NeverEnables_OwnKeyOnly()
    {
        Environment.SetEnvironmentVariable("FEATURE_DEFINITELY_NOT_A_FLAG", null);
        Flags.ResetProvider();
        try
        {
            // A name absent from the registry resolves via registryDefault -> OFF.
            Assert.False(Flags.IsEnabled("definitely_not_a_flag"));
            Assert.False(Flags.IsEnabled("__class__"));
        }
        finally
        {
            Flags.ResetProvider();
        }
    }

    [Fact]
    public void EnvFloor_ExactlyTrue_Enables()
    {
        Environment.SetEnvironmentVariable(EnvVar, "true");
        Flags.ResetProvider();
        try
        {
            Assert.True(Flags.IsEnabled("new_greeting"));
        }
        finally
        {
            ClearEnv();
            Flags.ResetProvider();
        }
    }

    [Theory]
    [InlineData("TRUE")]
    [InlineData("True")]
    [InlineData("1")]
    [InlineData("yes")]
    [InlineData(" true")]
    [InlineData("true ")]
    [InlineData("")]
    public void EnvFloor_NonExactTrue_DoesNotEnable(string raw)
    {
        Environment.SetEnvironmentVariable(EnvVar, raw);
        Flags.ResetProvider();
        try
        {
            Assert.False(Flags.IsEnabled("new_greeting"));
        }
        finally
        {
            ClearEnv();
            Flags.ResetProvider();
        }
    }

    [Fact]
    public void EnvName_MapsToFeatureScreamingSnake()
    {
        Assert.Equal("FEATURE_NEW_GREETING", Flags.EnvName("new_greeting"));
    }

    [Fact]
    public void SetProvider_SwapsActiveProvider_ThenResetRestoresFloor()
    {
        ClearEnv();
        Flags.ResetProvider();
        try
        {
            Assert.False(Flags.IsEnabled("new_greeting"));
            Flags.SetProvider(new AlwaysOnProvider());
            Assert.True(Flags.IsEnabled("new_greeting"));
            Flags.ResetProvider();
            Assert.False(Flags.IsEnabled("new_greeting"));
        }
        finally
        {
            Flags.ResetProvider();
        }
    }

    [Fact]
    public void SetProvider_Null_FailsSafeOff()
    {
        ClearEnv();
        try
        {
            Flags.SetProvider(null);
            Assert.False(Flags.IsEnabled("new_greeting"));
        }
        finally
        {
            Flags.ResetProvider();
        }
    }

    private sealed class AlwaysOnProvider : FlagProvider
    {
        public bool IsEnabled(string name) => true;
    }
}

/// <summary>Shared collection so the flag test classes never run in parallel (they mutate global state).</summary>
[CollectionDefinition("Flags")]
public class FlagsCollection
{
}
