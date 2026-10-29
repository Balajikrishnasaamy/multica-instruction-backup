import java.io.BufferedWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.platform.engine.reporting.ReportEntry;
import org.opentest4j.AssertionFailedError;
import org.junit.platform.engine.TestExecutionResult;
import org.junit.platform.engine.support.descriptor.ClassSource;
import org.junit.platform.engine.support.descriptor.MethodSource;
import org.junit.platform.launcher.Launcher;
import org.junit.platform.launcher.LauncherDiscoveryRequest;
import org.junit.platform.launcher.TestExecutionListener;
import org.junit.platform.launcher.TestIdentifier;
import org.junit.platform.launcher.TestPlan;
import org.junit.platform.launcher.core.LauncherDiscoveryRequestBuilder;
import org.junit.platform.launcher.core.LauncherFactory;
import org.junit.platform.launcher.listeners.SummaryGeneratingListener;
import org.junit.platform.launcher.listeners.TestExecutionSummary;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectClass;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectMethod;

/**
 * Minimal JUnit 5 console runner used by run_test.sh.
 * Args: fully.qualified.Class or fully.qualified.Class#method
 * -Drunner.out=<file> writes one TSV record per test: class, method, display, status, millis, message, stacktrace,
 * entries, expected, actual (tabs/newlines/backslashes escaped as \t \n \\).
 * entries = what the test published with TestReporter.publishEntry(key, value) (convention: input, output, expected),
 * as key \u0001 value pairs joined by \u0002. expected/actual come from a failed assertion (assertEquals etc.).
 */
public class Runner {
	static String esc(String s) {
		if (s == null) return "";
		return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "").replace("\n", "\\n");
	}

	static class Recorder implements TestExecutionListener {
		final BufferedWriter out;
		final Map<String, Long> started = new HashMap<>();
		final Map<String, List<String>> entries = new HashMap<>();
		Recorder(BufferedWriter out) { this.out = out; }

		@Override public void reportingEntryPublished(TestIdentifier id, ReportEntry entry) {
			List<String> l = entries.computeIfAbsent(id.getUniqueId(), k -> new ArrayList<>());
			for (Map.Entry<String, String> e : entry.getKeyValuePairs().entrySet())
				l.add(e.getKey() + "\u0001" + e.getValue());
		}

		@Override public void executionSkipped(TestIdentifier id, String reason) { write(id, "SKIPPED", 0, reason, null, null, null, null); }
		@Override public void executionStarted(TestIdentifier id) { started.put(id.getUniqueId(), System.nanoTime()); }
		@Override public void executionFinished(TestIdentifier id, TestExecutionResult r) {
			Long t0 = started.get(id.getUniqueId());
			long ms = t0 == null ? 0 : (System.nanoTime() - t0) / 1_000_000;
			String status;
			switch (r.getStatus()) {
				case SUCCESSFUL: status = "PASSED"; break;
				case ABORTED: status = "ABORTED"; break;
				default: status = "FAILED";
			}
			// A passing container is not interesting; a failing one (e.g. @BeforeAll, class init) must be shown.
			if (!id.isTest() && r.getStatus() == TestExecutionResult.Status.SUCCESSFUL) return;
			String msg = null, trace = null, expected = null, actual = null;
			if (r.getThrowable().isPresent()) {
				Throwable th = r.getThrowable().get();
				for (Throwable c = th; c != null; c = c.getCause() == c ? null : c.getCause()) {
					if (c instanceof AssertionFailedError) {
						AssertionFailedError af = (AssertionFailedError) c;
						if (af.isExpectedDefined()) expected = af.getExpected().getStringRepresentation();
						if (af.isActualDefined()) actual = af.getActual().getStringRepresentation();
						break;
					}
				}
				msg = th.getClass().getName() + (th.getMessage() == null ? "" : ": " + th.getMessage());
				StringWriter sw = new StringWriter();
				th.printStackTrace(new PrintWriter(sw));
				trace = sw.toString();
			}
			List<String> ent = entries.remove(id.getUniqueId());
			write(id, status, ms, msg, trace, ent == null ? null : String.join("\u0002", ent), expected, actual);
		}

		synchronized void write(TestIdentifier id, String status, long ms, String msg, String trace, String ent, String expected, String actual) {
			String cls = "", method = "";
			if (id.getSource().isPresent()) {
				if (id.getSource().get() instanceof MethodSource) {
					MethodSource ms2 = (MethodSource) id.getSource().get();
					cls = ms2.getClassName(); method = ms2.getMethodName();
				} else if (id.getSource().get() instanceof ClassSource) {
					cls = ((ClassSource) id.getSource().get()).getClassName();
				}
			}
			if (!id.isTest() && "SKIPPED".equals(status) && method.isEmpty()) method = "(whole class)";
			try {
				out.write(String.join("\t", esc(cls), esc(method), esc(id.getDisplayName()), status, Long.toString(ms), esc(msg), esc(trace), esc(ent), esc(expected), esc(actual)));
				out.write("\n");
				out.flush();
			} catch (Exception e) { throw new RuntimeException(e); }
		}
	}

	public static void main(String[] args) throws Exception {
		LauncherDiscoveryRequestBuilder b = LauncherDiscoveryRequestBuilder.request();
		for (String a : args) b.selectors(a.contains("#") ? selectMethod(a) : selectClass(a));
		LauncherDiscoveryRequest req = b.build();
		Launcher launcher = LauncherFactory.create();
		SummaryGeneratingListener l = new SummaryGeneratingListener();
		String outFile = System.getProperty("runner.out");
		BufferedWriter w = outFile == null ? null : Files.newBufferedWriter(Paths.get(outFile), StandardCharsets.UTF_8);
		if (w != null) launcher.execute(req, l, new Recorder(w)); else launcher.execute(req, l);
		if (w != null) w.close();
		TestExecutionSummary s = l.getSummary();
		PrintWriter pw = new PrintWriter(System.out);
		s.printFailuresTo(pw, 25);
		pw.flush();
		long found = s.getTestsFoundCount(), ok = s.getTestsSucceededCount(), failed = s.getTestsFailedCount(), skipped = s.getTestsSkippedCount(), aborted = s.getTestsAbortedCount();
		System.out.println("RESULT found=" + found + " passed=" + ok + " failed=" + failed + " skipped=" + skipped + " aborted=" + aborted + " containers_failed=" + s.getContainersFailedCount());
		System.exit(found > 0 && failed == 0 && s.getContainersFailedCount() == 0 && ok > 0 ? 0 : 1);
	}
}
