package com.fari.metrics;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Parses {@code gcClassHistogram}'s plain-text jmap-histo-style report.
 * HotSpot family only (docs/specs/open-questions.md known risk #8) — a
 * missing/unrecognized header throws, so the caller degrades to
 * {@link ClassHistogramResult#unavailable} instead of showing garbage.
 */
final class ClassHistogramParser {

    private static final Pattern HEADER = Pattern.compile(
            "^\\s*num\\s+#instances\\s+#bytes\\s+class name.*$");
    private static final Pattern ROW = Pattern.compile(
            "^\\s*\\d+:\\s+(\\d+)\\s+(\\d+)\\s+(.+)$");
    // Strips the JDK 9+ "(module@version)" suffix HotSpot appends to class
    // names — the exact format break VisualVM's Histogram18/Histogram19
    // split exists to handle (see open-questions.md known risk #8).
    private static final Pattern MODULE_SUFFIX = Pattern.compile("\\s+\\([^()]*@[^()]*\\)\\s*$");

    private ClassHistogramParser() {
    }

    static List<ClassHistogramEntry> parse(String report) {
        String[] lines = report.split("\n", -1);
        boolean sawHeader = false;
        List<ClassHistogramEntry> entries = new ArrayList<>();
        for (String line : lines) {
            if (!sawHeader) {
                if (HEADER.matcher(line).matches()) {
                    sawHeader = true;
                }
                continue;
            }
            Matcher m = ROW.matcher(line);
            if (!m.matches()) {
                continue;
            }
            long instances = Long.parseLong(m.group(1));
            long bytes = Long.parseLong(m.group(2));
            String className = MODULE_SUFFIX.matcher(m.group(3).trim()).replaceFirst("").trim();
            entries.add(new ClassHistogramEntry(className, instances, bytes));
        }
        if (!sawHeader) {
            throw new IllegalStateException("gcClassHistogram output missing expected header — unrecognized format");
        }
        return entries;
    }
}
