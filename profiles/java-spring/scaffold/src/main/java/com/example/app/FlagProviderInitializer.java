package com.example.app;

import org.springframework.stereotype.Component;

/**
 * The {@code FLAG_FILE} boot gate — installs the live file-config provider at startup if
 * configured.
 *
 * <p>The Spring counterpart to the go {@code configureProvider()} / python {@code serve()} boot
 * wiring: when {@code FLAG_FILE} is set, the reference {@link FileConfigProvider} is installed into
 * the {@link FeatureFlags} seam BEFORE the server serves traffic, so the running server's {@code
 * /greeting} reflects live file flips with no restart. Unset -&gt; the env floor (default). The
 * pure {@link #configure(String)} is extracted so the wiring is unit-tested without mutating the
 * process environment.
 */
@Component
public class FlagProviderInitializer {

  /** Reads {@code FLAG_FILE} from the environment and installs the live provider if present. */
  public FlagProviderInitializer() {
    configure(System.getenv("FLAG_FILE"));
  }

  /**
   * Installs the file-config live provider when {@code flagFile} is a non-blank path.
   *
   * @param flagFile the app-configured flag-file path (may be {@code null} / blank -&gt; no-op)
   */
  static void configure(String flagFile) {
    if (flagFile != null && !flagFile.isBlank()) {
      FeatureFlags.setProvider(new FileConfigProvider(flagFile));
    }
  }
}
