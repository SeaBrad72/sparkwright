package com.example.app;

import com.example.app.FeatureFlags.FlagProvider;
import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.StreamReadConstraints;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Set;

/**
 * Reference LIVE flag provider — a file-config {@link FlagProvider} that reflects changes WITHOUT a
 * restart (java-spring profile).
 *
 * <p>This is the reference implementation of the live slot in the {@link FeatureFlags} seam: it
 * re-reads a JSON flag file on every resolution, so rewriting the file flips behaviour in the SAME
 * running process (a live runtime flip, not the env floor's restart-to-toggle). A SaaS provider
 * (OpenFeature / Unleash / LaunchDarkly) is an adopter-pluggable alternative implementing the same
 * {@link FlagProvider} — swap it in via {@link FeatureFlags#setProvider} with no change to callers
 * of {@link FeatureFlags#isEnabled}.
 *
 * <p>TRUST BOUNDARY: {@code path} is APP-CONFIGURED (an operator-controlled deploy artifact), NOT
 * end-user input. The file CONTENT is still treated as untrusted (it can be corrupted/tampered), so
 * resolution is fully fail-safe and injection-safe:
 *
 * <ul>
 *   <li>fail-safe: a missing / unreadable / unparseable / oversized / DEEPLY-NESTED file, a
 *       non-object payload (array/null/scalar), a non-bool value, or a flag absent from the file
 *       all fall back to the registry default (OFF). Resolution never throws and never enables on
 *       ANY file content. An oversized file is rejected by a 1 MiB byte cap BEFORE parse; a
 *       deeply-nested or huge-string tampered file is rejected by Jackson's {@link
 *       StreamReadConstraints} (the parser throws — caught — before it can recurse the stack into a
 *       StackOverflow), so a tamperer cannot turn "flip a flag" into "crash the resolver" — the DoS
 *       class the Slice-2 review caught, regression-locked by {@code
 *       deeplyNestedPayloadIsRejectedWithoutCrashing}.
 *   <li>no injection: {@code FORBIDDEN_KEYS} ({@code __proto__}/{@code constructor}/{@code
 *       prototype} and dunder-ish keys) are rejected outright; only the SPECIFIC flag key is read —
 *       the parsed JSON is NEVER spread/merged into anything.
 *   <li>strict coercion: only the JSON boolean {@code true} enables (a {@code "true"} string, 1,
 *       etc. stay OFF — mirrors the env floor's strict {@code == "true"}).
 * </ul>
 *
 * <p>PERFORMANCE CAVEAT: this provider does a SYNCHRONOUS file read on EVERY {@code isEnabled}
 * call. That is fine for a kill-switch and for the shipped default (the env floor does no FS read
 * at all), but a profile/adopter that wires the file provider onto a HOT request path should add an
 * mtime-gated cache.
 */
public final class FileConfigProvider implements FlagProvider {

  /**
   * Caps the flag file read at 1 MiB. A flag file is tiny (a handful of booleans); 1 MiB is very
   * generous. The cap bounds memory so an oversized or tampered file can never be slurped in.
   */
  private static final int MAX_FILE_BYTES = 1 << 20;

  /**
   * Names that must never be resolved from file data (builtin-shadowing / prototype-pollution
   * vectors).
   */
  private static final Set<String> FORBIDDEN_KEYS = Set.of("__proto__", "constructor", "prototype");

  /**
   * A Jackson mapper hardened with {@link StreamReadConstraints} so a deeply-nested or huge-string
   * tampered file throws (and is caught) rather than exhausting the stack or heap.
   */
  private static final ObjectMapper MAPPER = buildHardenedMapper();

  private final Path path;

  /**
   * Creates a live provider whose {@link #isEnabled} re-reads {@code path} per call.
   *
   * @param path the app-configured flag-file path (content untrusted)
   */
  public FileConfigProvider(String path) {
    this.path = Path.of(path);
  }

  private static ObjectMapper buildHardenedMapper() {
    StreamReadConstraints constraints =
        StreamReadConstraints.builder()
            .maxNestingDepth(64)
            .maxStringLength(200_000)
            .maxNumberLength(1_000)
            .build();
    JsonFactory factory = JsonFactory.builder().streamReadConstraints(constraints).build();
    return new ObjectMapper(factory);
  }

  /**
   * Resolves {@code name} from the file, fully fail-safe: any error, oversize, non-object, missing
   * key, non-bool, or forbidden key falls back to the registry default (OFF). Never throws.
   *
   * @param name the flag name
   * @return {@code true} iff the file carries {@code name} as JSON boolean {@code true}
   */
  @Override
  public boolean isEnabled(String name) {
    boolean fallback = FeatureFlags.registryDefault(name);

    // Reject dunder-ish / pollution keys outright — never resolved from file data.
    if (FORBIDDEN_KEYS.contains(name) || (name.startsWith("__") && name.endsWith("__"))) {
      return fallback;
    }

    byte[] data = readCapped();
    if (data == null) {
      return fallback;
    }

    try {
      // readTree over the hardened mapper: a deeply-nested / oversized-string payload throws a
      // StreamConstraintsException (an IOException) BEFORE recursing, so the parse cannot DoS.
      JsonNode root = MAPPER.readTree(data);
      if (root == null || !root.isObject()) {
        return fallback;
      }
      // Read ONLY the requested key — the untrusted object is never spread/merged.
      JsonNode value = root.get(name);
      // Strict: only a JSON boolean enables (a "true" string, 1, null, or object stay OFF).
      if (value == null || !value.isBoolean()) {
        return fallback;
      }
      return value.booleanValue();
    } catch (Exception e) {
      // Any parse/constraint failure on tampered content -> fail-safe OFF, never propagate.
      return fallback;
    }
  }

  /**
   * Reads at most {@link #MAX_FILE_BYTES} bytes, rejecting anything larger. Reads one byte past the
   * cap so an oversized file is detected and rejected without slurping the whole thing into memory.
   *
   * @return the file bytes, or {@code null} on any error or oversize (fail-safe OFF)
   */
  private byte[] readCapped() {
    // NOTE: path is an app-configured operator artifact, not end-user input; its CONTENT is treated
    // as untrusted and the read is byte-capped here.
    try (InputStream in = Files.newInputStream(path)) {
      byte[] data = in.readNBytes(MAX_FILE_BYTES + 1);
      if (data.length > MAX_FILE_BYTES) {
        return null;
      }
      return data;
    } catch (Exception e) {
      return null;
    }
  }
}
