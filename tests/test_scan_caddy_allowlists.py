import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "skills/centralize-caddy-whitelist/scripts/scan_caddy_allowlists.py"
SPEC = importlib.util.spec_from_file_location("scanner", SCRIPT)
SCANNER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = SCANNER
SPEC.loader.exec_module(SCANNER)


class ScannerTests(unittest.TestCase):
    def test_complex_config_keeps_distinct_policy_groups(self):
        path = Path(__file__).parent / "fixtures/complex.Caddyfile"
        results = SCANNER.scan_file(path)

        self.assertEqual(2, len(results))
        self.assertEqual("restricted_clients", results[0].snippet)
        self.assertEqual("migrated_nginx_allowed_clients", results[1].snippet)
        self.assertNotEqual(set(results[0].addresses), set(results[1].addresses))

    def test_preserves_snippet_groups_and_detects_unparsed_tokens(self):
        config = """
(restricted_clients) {
    @allowed remote_ip 192.0.2.10 10.0.0.0/8
}

(other_clients) {
    @allowed {
        remote_ip 198.51.100.20 {env.EXTRA_IP}
    }
}
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Caddyfile"
            path.write_text(config, encoding="utf-8")
            results = SCANNER.scan_file(path)

        self.assertEqual(2, len(results))
        self.assertEqual("restricted_clients", results[0].snippet)
        self.assertEqual("allowed", results[0].matcher)
        self.assertEqual(["192.0.2.10", "10.0.0.0/8"], results[0].addresses)
        self.assertEqual("other_clients", results[1].snippet)
        self.assertEqual("allowed", results[1].matcher)
        self.assertIn("env.EXTRA_IP", " ".join(results[1].unparsed))

    def test_emit_fragment_deduplicates_in_input_order(self):
        occurrence = SCANNER.Occurrence("Caddyfile", 1, "clients", "allowed", ["192.0.2.1", "192.0.2.1", "::1"], [])
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(0, SCANNER.emit_fragment([occurrence], "clients", "allowed"))
        self.assertEqual("@allowed remote_ip 192.0.2.1 ::1\n", output.getvalue())


if __name__ == "__main__":
    unittest.main()
