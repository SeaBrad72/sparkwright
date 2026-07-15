package com.example.app;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.app.FeatureFlags.FlagProvider;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Unit tests for {@link FileConfigProvider} — the reference LIVE file provider. Covers the live
 * flip (re-read per call), and the full fail-safe / injection-safe matrix a tampered, untrusted
 * flag file must survive without ever crashing or enabling: missing, forbidden-key, oversized,
 * malformed, non-object, missing-key, non-bool, and deeply-nested payloads.
 */
class FileConfigProviderTest {

  private static void write(Path file, String content) throws IOException {
    Files.writeString(file, content, StandardCharsets.UTF_8);
  }

  @Test
  void liveFlipReflectsRewriteWithoutRestart(@TempDir Path dir) throws IOException {
    Path file = dir.resolve("flags.json");
    write(file, "{\"new_greeting\": true}");
    FlagProvider provider = new FileConfigProvider(file.toString());

    assertThat(provider.isEnabled("new_greeting")).isTrue();

    // Rewrite the SAME file — a re-read per call must observe the flip with no restart.
    write(file, "{\"new_greeting\": false}");
    assertThat(provider.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void missingFileFailsSafeOff(@TempDir Path dir) {
    FlagProvider provider = new FileConfigProvider(dir.resolve("absent.json").toString());
    assertThat(provider.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void forbiddenKeysAreRejectedEvenWhenTrue(@TempDir Path dir) throws IOException {
    Path file = dir.resolve("flags.json");
    write(
        file, "{\"__proto__\": true, \"constructor\": true, \"prototype\": true, \"__x__\": true}");
    FlagProvider provider = new FileConfigProvider(file.toString());

    assertThat(provider.isEnabled("__proto__")).isFalse();
    assertThat(provider.isEnabled("constructor")).isFalse();
    assertThat(provider.isEnabled("prototype")).isFalse();
    // Dunder-ish keys (start AND end with __) are rejected outright too.
    assertThat(provider.isEnabled("__x__")).isFalse();
  }

  @Test
  void oversizedFileIsRejectedBeforeParse(@TempDir Path dir) throws IOException {
    Path file = dir.resolve("huge.json");
    // 1 MiB + 1 byte of valid-looking JSON padding -> rejected by the byte cap.
    StringBuilder sb = new StringBuilder("{\"new_greeting\": true, \"pad\": \"");
    sb.append("a".repeat((1 << 20) + 1));
    sb.append("\"}");
    write(file, sb.toString());
    FlagProvider provider = new FileConfigProvider(file.toString());

    assertThat(provider.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void malformedJsonFailsSafeOff(@TempDir Path dir) throws IOException {
    Path file = dir.resolve("bad.json");
    write(file, "{\"new_greeting\": tru");
    FlagProvider provider = new FileConfigProvider(file.toString());
    assertThat(provider.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void nonObjectPayloadsFailSafeOff(@TempDir Path dir) throws IOException {
    Path file = dir.resolve("flags.json");
    FlagProvider provider = new FileConfigProvider(file.toString());

    write(file, "[true]");
    assertThat(provider.isEnabled("new_greeting")).isFalse();
    write(file, "null");
    assertThat(provider.isEnabled("new_greeting")).isFalse();
    write(file, "true");
    assertThat(provider.isEnabled("new_greeting")).isFalse();
    write(file, "42");
    assertThat(provider.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void missingKeyFallsBackToRegistryDefault(@TempDir Path dir) throws IOException {
    Path file = dir.resolve("flags.json");
    write(file, "{\"other_flag\": true}");
    FlagProvider provider = new FileConfigProvider(file.toString());
    assertThat(provider.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void nonBooleanValueDoesNotEnable(@TempDir Path dir) throws IOException {
    Path file = dir.resolve("flags.json");
    FlagProvider provider = new FileConfigProvider(file.toString());

    // Strict coercion: only a JSON boolean true enables. String/number/object stay OFF.
    write(file, "{\"new_greeting\": \"true\"}");
    assertThat(provider.isEnabled("new_greeting")).isFalse();
    write(file, "{\"new_greeting\": 1}");
    assertThat(provider.isEnabled("new_greeting")).isFalse();
    write(file, "{\"new_greeting\": {}}");
    assertThat(provider.isEnabled("new_greeting")).isFalse();
  }

  @Test
  void presentBooleanTrueEnablesRequestedKeyOnly(@TempDir Path dir) throws IOException {
    Path file = dir.resolve("flags.json");
    write(file, "{\"new_greeting\": false}");
    FlagProvider provider = new FileConfigProvider(file.toString());
    assertThat(provider.isEnabled("new_greeting")).isFalse();

    write(file, "{\"new_greeting\": true}");
    assertThat(provider.isEnabled("new_greeting")).isTrue();
  }

  @Test
  void deeplyNestedPayloadIsRejectedWithoutCrashing(@TempDir Path dir) throws IOException {
    Path file = dir.resolve("nested.json");
    // ~2000 levels of nesting: under the 1 MiB byte cap but far past the parser's
    // nesting-depth guard, so the parser throws (caught) rather than overflowing the
    // stack — the tampered-file DoS class the Slice-2 review caught, regression-locked.
    int depth = 2000;
    write(file, "[".repeat(depth) + "]".repeat(depth));
    FlagProvider provider = new FileConfigProvider(file.toString());

    assertThat(provider.isEnabled("new_greeting")).isFalse();
  }
}
