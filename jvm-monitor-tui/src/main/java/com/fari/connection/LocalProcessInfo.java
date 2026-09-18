package com.fari.connection;

/** PID + display name only — no attach performed to build this list. */
public record LocalProcessInfo(String pid, String displayName, String jvmArgs) {
}
