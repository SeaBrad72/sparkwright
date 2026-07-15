package com.example.app;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.app.FeatureFlags.FlagProvider;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for {@link FeatureFlags} — the registry + provider seam (env floor). Exercises the
 * default-OFF registry, the own-key-only fallback, the strict env parse, and the pluggable provider
 * slot (swap / reset / nil fail-safe). The live file provider is covered by {@link
 * FileConfigProviderTest}.
 */
class FeatureFlagsTest {

  @AfterEach
  void restoreFloor() {
    // Never leak a swapped provider into another test — the slot is process-global.
    FeatureFlags.resetProvider();
  }

  @Test
  void registryDefaultsOffForKnownFlag() {
    // No env var set for FEATURE_NEW_GREETING -> registry default OFF.
    assertThat(FeatureFlags.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void unknownFlagIsOwnKeyOnlyOff() {
    // A name absent from the registry can never resolve truthy via the floor.
    assertThat(FeatureFlags.isEnabled("does_not_exist")).isFalse();
    assertThat(FeatureFlags.isEnabled("__class__")).isFalse();
  }

  @Test
  void envNameMapsSnakeToScreamingWithPrefix() {
    assertThat(FeatureFlags.envName("new_greeting")).isEqualTo("FEATURE_NEW_GREETING");
  }

  @Test
  void envParseIsStrictOnlyExactTrueEnables() {
    // Only the exact string "true" enables — TRUE/1/yes/empty do NOT.
    assertThat(FeatureFlags.resolveEnvValue("true", "new_greeting")).isTrue();
    assertThat(FeatureFlags.resolveEnvValue("TRUE", "new_greeting")).isFalse();
    assertThat(FeatureFlags.resolveEnvValue("1", "new_greeting")).isFalse();
    assertThat(FeatureFlags.resolveEnvValue("yes", "new_greeting")).isFalse();
    assertThat(FeatureFlags.resolveEnvValue("", "new_greeting")).isFalse();
  }

  @Test
  void envUnsetFallsBackToRegistryDefault() {
    // A null raw value (env unset) falls through to the registry default (OFF here).
    assertThat(FeatureFlags.resolveEnvValue(null, "new_greeting")).isFalse();
    assertThat(FeatureFlags.resolveEnvValue(null, "does_not_exist")).isFalse();
  }

  @Test
  void envProviderResolvesThroughFloor() {
    // The default active provider is the env floor; exercise its full path.
    assertThat(FeatureFlags.envProvider.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void setProviderSwapsAndResetRestoresFloor() {
    FlagProvider allOn = name -> true;
    FeatureFlags.setProvider(allOn);
    assertThat(FeatureFlags.isEnabled("new_greeting")).isTrue();
    assertThat(FeatureFlags.isEnabled("anything")).isTrue();

    FeatureFlags.resetProvider();
    assertThat(FeatureFlags.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void nilProviderFailsSafeOff() {
    // A defensively-installed null provider must resolve OFF, never NPE.
    FeatureFlags.setProvider(null);
    assertThat(FeatureFlags.isEnabled("new_greeting")).isFalse();
  }
}
