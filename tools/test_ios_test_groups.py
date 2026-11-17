import unittest
from run_ios_test_group import groups


class TestNativeGroups(unittest.TestCase):
    def test_live_failures_are_separate_not_lost(self):
        result = groups("func testLiveSource() {} func testOpusCodec() {} func testNormalization() {}")
        self.assertEqual(result["network"], ["testLiveSource"])
        self.assertEqual(result["deterministic"], ["testOpusCodec", "testNormalization"])
        self.assertEqual(sum(map(len, result.values())), 3)

    def test_async_and_actor_tests_are_not_omitted(self):
        result = groups("@MainActor func testOffline() async throws {}\nfunc testLiveOpus() async throws {}")
        self.assertEqual(result["deterministic"], ["testOffline"])
        self.assertEqual(result["network"], ["testLiveOpus"])

    def test_empty_or_duplicate_discovery_fails_closed(self):
        for source in ["", "func testOne() {} func testOne() {}"]:
            with self.assertRaises(ValueError):
                groups(source)


if __name__ == "__main__":
    unittest.main()
