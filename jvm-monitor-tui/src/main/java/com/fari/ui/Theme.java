package com.fari.ui;

import dev.tamboui.style.Color;

/** Plain color constants for the mock's palette (docs/specs/ui-view). */
public final class Theme {

    private Theme() {
    }

    public static final String APP_NAME = "JVM MONITOR";
    public static final String APP_VERSION = loadAppVersion();

    private static String loadAppVersion() {
        var properties = new java.util.Properties();
        try (var in = Theme.class.getResourceAsStream("/application.properties")) {
            if (in != null) {
                properties.load(in);
            }
        } catch (java.io.IOException ignored) {
            // Falls through to the "unknown" default below.
        }
        String version = properties.getProperty("app.version");
        return version == null || version.isBlank() ? "v?" : "v" + version;
    }

    public static final Color BACKGROUND = Color.hex("#161826");
    public static final Color TEXT_PRIMARY = Color.hex("#e9e9ed");
    public static final Color TEXT_SECONDARY = Color.hex("#b2b6ca");
    public static final Color TEXT_MUTED = Color.hex("#75798c");
    public static final Color ACCENT = Color.hex("#9184d9");
    public static final Color ACCENT_LIGHT = Color.hex("#d2cefd");
    public static final Color BORDER = Color.hex("#E3E0FF");
    // Alternate-row background for table zebra-striping — one step lighter
    // than BACKGROUND, subtle enough not to compete with row text/highlight.
    public static final Color ROW_ALT = Color.hex("#1e2133");
    public static final Color STATUS_GOOD = ACCENT;
    public static final Color STATUS_BAD = Color.hex("#e06c75");
}
