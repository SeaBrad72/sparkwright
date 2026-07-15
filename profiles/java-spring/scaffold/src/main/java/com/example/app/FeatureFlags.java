package com.example.app;

import java.util.Locale;
import java.util.Map;

/**
 * Feature-flag registry + resolver SEAM — the kit's kill-switch (java-spring profile).
 *
 * <p>A typed flag module whose default is OFF, so an unset / unknown / malformed value can never
 * silently enable a feature (fail-safe). This module is a PROVIDER SEAM (the shape the whole
 * profile fan-out replicates):
 *
 * <ul>
 *   <li>the FLOOR provider ({@link #envProvider}) is env-driven and restart-to-toggle — dark-launch
 *       + a real kill-switch, but NOT a live runtime flip;
 *   <li>a pluggable live slot ({@link #setProvider}) accepts any {@link FlagProvider} — e.g. the
 *       reference file-config live provider ({@link FileConfigProvider}, flips WITHOUT a restart)
 *       or an adopter's SaaS provider (OpenFeature/Unleash/LaunchDarkly) implementing the same
 *       interface.
 * </ul>
 *
 * <p>The public API stays {@link #isEnabled(String)} and delegates to whichever provider is active.
 * Adding a flag = one entry in {@link #FLAGS} (the single place to enumerate live flags, so
 * retiring one is a known list, not a code hunt).
 *
 * <p>Thread-safe: the shared provider slot is guarded by a lock because {@code setProvider} /
 * {@code resetProvider} / {@code isEnabled} touch it from multiple threads (integration tests hit
 * it concurrently).
 */
public final class FeatureFlags {

  private FeatureFlags() {}

  /**
   * The single typed registry — the one place flags are enumerated. Default OFF: a name absent here
   * (or stored {@code false}) can never resolve truthy.
   */
  private static final Map<String, Boolean> FLAGS = Map.of("new_greeting", Boolean.FALSE);

  /**
   * The seam contract every provider (env floor, file-config, SaaS) implements. Public so an
   * adopter can plug in their own provider.
   */
  public interface FlagProvider {
    /**
     * Resolves a flag by name.
     *
     * @param name the flag name
     * @return {@code true} iff the flag is enabled by this provider
     */
    boolean isEnabled(String name);
  }

  /** The pluggable seam guard — protects the shared {@link #activeProvider} slot. */
  private static final Object LOCK = new Object();

  /**
   * Maps a snake_case flag to a {@code FEATURE_}-prefixed SCREAMING_SNAKE env var: {@code
   * new_greeting} -> {@code FEATURE_NEW_GREETING}.
   *
   * @param name the snake_case flag name
   * @return the environment-variable name
   */
  static String envName(String name) {
    return "FEATURE_" + name.toUpperCase(Locale.ROOT);
  }

  /**
   * Own-key-only, strict-boolean fallback. A name that is not a registry key (incl. dunder-ish
   * collisions like {@code __class__}/{@code constructor}) must NOT resolve truthy — fail-safe OFF,
   * not open. Only a registry key whose stored value is exactly {@code true} enables.
   *
   * @param name the flag name
   * @return the registry default for {@code name}
   */
  static boolean registryDefault(String name) {
    return Boolean.TRUE.equals(FLAGS.get(name));
  }

  /**
   * Pure strict-parse of an env raw value against the floor rules. Exposed package-private so the
   * strict semantics are unit-testable without mutating the process environment. True ONLY when
   * {@code raw} is exactly {@code "true"}; a null raw (env unset) falls back to the registry
   * default. {@code "TRUE"}/{@code "1"}/{@code "yes"} do NOT enable.
   *
   * @param raw the raw env value (or {@code null} if unset)
   * @param name the flag name (used for the unset fallback)
   * @return the resolved value under the strict floor rules
   */
  static boolean resolveEnvValue(String raw, String name) {
    if (raw == null) {
      return registryDefault(name);
    }
    return raw.equals("true");
  }

  /**
   * The FLOOR resolver: env-driven, restart-to-toggle, fail-safe OFF.
   *
   * @param name the flag name
   * @return the env-floor resolution for {@code name}
   */
  static boolean envDefault(String name) {
    return resolveEnvValue(System.getenv(envName(name)), name);
  }

  /** The env floor — the default active provider installed below. */
  static final FlagProvider envProvider = FeatureFlags::envDefault;

  /** The pluggable seam slot; default = the env floor. Guarded by {@link #LOCK}. */
  private static FlagProvider activeProvider = envProvider;

  /**
   * Installs a live provider into the seam (e.g. the file-config live provider). A {@code null}
   * provider is tolerated and fails safe OFF at resolution time.
   *
   * @param provider the provider to install (may be {@code null})
   */
  public static void setProvider(FlagProvider provider) {
    synchronized (LOCK) {
      activeProvider = provider;
    }
  }

  /** Restores the env floor as the active provider. */
  public static void resetProvider() {
    synchronized (LOCK) {
      activeProvider = envProvider;
    }
  }

  /**
   * Public API — delegates to the active provider under the lock. A {@code null} active provider
   * (defensive) resolves OFF rather than throwing.
   *
   * @param name the flag name
   * @return {@code true} iff the active provider enables {@code name}
   */
  public static boolean isEnabled(String name) {
    FlagProvider provider;
    synchronized (LOCK) {
      provider = activeProvider;
    }
    if (provider == null) {
      return false;
    }
    return provider.isEnabled(name);
  }
}
