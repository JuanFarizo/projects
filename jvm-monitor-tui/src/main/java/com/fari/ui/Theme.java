package com.fari.ui;

import dev.tamboui.style.Color;

/** Plain color constants for the mock's palette (docs/spec/ui-view). */
public final class Theme {

    private Theme() {
    }

    public static final Color BACKGROUND = Color.hex("#161826");
    public static final Color TEXT_PRIMARY = Color.hex("#e9e9ed");
    public static final Color TEXT_SECONDARY = Color.hex("#b2b6ca");
    public static final Color TEXT_MUTED = Color.hex("#75798c");
    public static final Color ACCENT = Color.hex("#9184d9");
    public static final Color ACCENT_LIGHT = Color.hex("#d2cefd");
    public static final Color BORDER = Color.hex("#E3E0FF");
    public static final Color STATUS_GOOD = ACCENT;
    public static final Color STATUS_BAD = Color.hex("#e06c75");
}
