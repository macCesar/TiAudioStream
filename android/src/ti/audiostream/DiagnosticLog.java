package ti.audiostream;

import org.appcelerator.kroll.common.Log;

/** Keeps native diagnostics separate from the public error event payload. */
final class DiagnosticLog {
	private DiagnosticLog() {}
	static String sanitize(String message) {
		if (message == null) return "";
		String safe = message.replaceAll("(?i)\\b[a-z][a-z0-9+.-]*://[^\\s<>\"']+", "[URL]")
			.replaceAll("[\\r\\n\\t]", " ");
		return safe.length() > 1024 ? safe.substring(0, 1024) : safe;
	}
	static void d(String tag, String message) { if (org.appcelerator.kroll.common.TiConfig.LOGD) Log.d(tag, sanitize(message)); }
	static void i(String tag, String message) { if (org.appcelerator.kroll.common.TiConfig.LOGD) Log.i(tag, sanitize(message)); }
	static void w(String tag, String message) { Log.w(tag, sanitize(message)); }
	static void e(String tag, String message) { Log.e(tag, sanitize(message)); }
}
