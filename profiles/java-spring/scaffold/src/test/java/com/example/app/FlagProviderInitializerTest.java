package com.example.app;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Unit test for the {@code FLAG_FILE} boot gate ({@link FlagProviderInitializer}). Exercises the
 * pure {@link FlagProviderInitializer#configure(String)} directly — the go {@code
 * configureProvider} counterpart — so the wiring is proven without mutating the process
 * environment.
 */
class FlagProviderInitializerTest {

  @AfterEach
  void restoreEnvFloor() {
    FeatureFlags.resetProvider();
  }

  @Test
  void configureWithFlagFileInstallsLiveProvider(@TempDir Path tmp) throws Exception {
    Path flagFile = tmp.resolve("flags.json");
    Files.writeString(flagFile, "{\"new_greeting\":true}", StandardCharsets.UTF_8);

    FlagProviderInitializer.configure(flagFile.toString());

    assertThat(FeatureFlags.isEnabled("new_greeting"))
        .as("the file provider is installed and reflects the file")
        .isTrue();
  }

  @Test
  void configureWithNullLeavesEnvFloor() {
    FlagProviderInitializer.configure(null);

    assertThat(FeatureFlags.isEnabled("new_greeting"))
        .as("no FLAG_FILE -> the env floor stays active (default OFF)")
        .isFalse();
  }

  @Test
  void configureWithBlankLeavesEnvFloor() {
    FlagProviderInitializer.configure("   ");

    assertThat(FeatureFlags.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void constructorReadsEnvWithoutError() {
    // FLAG_FILE is unset in the test env -> the no-arg constructor is a safe no-op.
    FlagProviderInitializer initializer = new FlagProviderInitializer();

    assertThat(initializer).isNotNull();
    assertThat(FeatureFlags.isEnabled("new_greeting")).isFalse();
  }
}
