import tempfile
import unittest
from pathlib import Path

from prediction import Predictor


class PredictorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        (self.base / "en_50k.txt").write_text(
            "help 500\nhello 1000\nhe 9000\nhelmet 100\nhero 100\n"
            "hello 10\nhe's 8000\nhe2 7000\nhéllo 9999\n"
            "hey -1\nheap invalid\nmalformed\n", encoding="utf-8")
        (self.base / "ru_50k.txt").write_text(
            "привет 1000\nпри 9000\nприехал 200\nпринять 400\n"
            "ёлка 20\nёлочка 10\nhello 9000\n", encoding="utf-8")
        self.predictor = Predictor(self.base)

    def test_lazy(self):
        self.assertFalse(self.predictor._dictionaries)
        self.predictor.suggest("he", "en")
        self.assertEqual(set(self.predictor._dictionaries), {"en"})

    def test_rank_and_strict_completion(self):
        self.assertEqual(self.predictor.suggest("he", "en"), ["hello", "help", "helmet"])
        self.assertEqual(self.predictor.suggest("при", "ru"), ["привет", "принять", "приехал"])

    def test_case_and_yo(self):
        self.assertEqual(self.predictor.suggest("ПрИ", "ru", 1), ["ПрИвет"])
        self.assertEqual(self.predictor.suggest("Пр", "ru", 1), ["При"])
        self.assertEqual(self.predictor.suggest("HE", "en", 1), ["HELLO"])
        self.assertEqual(self.predictor.suggest("ёл", "ru"), ["ёлка", "ёлочка"])

    def test_invalid_and_missing_matches(self):
        for prefix in ("", "h", "he ", "he2", None):
            self.assertEqual(self.predictor.suggest(prefix, "en"), [])
        self.assertEqual(self.predictor.suggest("hello", "en"), [])
        self.assertEqual(self.predictor.suggest("xx", "en"), [])
        self.assertEqual(self.predictor.suggest("he", "fr"), [])
        self.assertEqual(self.predictor.suggest("he", "en", 0), [])
        self.assertEqual(self.predictor.suggest("he", "en", -1), [])

    def test_missing_dictionary_is_explicit(self):
        (self.base / "ru_50k.txt").unlink()
        with self.assertRaises(FileNotFoundError):
            self.predictor.suggest("пр", "ru")


class RealDictionaryTests(unittest.TestCase):
    @unittest.skipUnless((Path(__file__).parent / "data" / "ru_50k.txt").exists(), "Dictionary not downloaded")
    def test_real_ru_en(self):
        predictor = Predictor()
        self.assertEqual(predictor.suggest("при", "ru", 1), ["привет"])
        self.assertIn("hello", predictor.suggest("hel", "en"))
        for language, prefix in (("en", "HE"), ("ru", "При")):
            for word in predictor.suggest(prefix, language):
                self.assertTrue(word.isalpha())
                self.assertTrue(word.startswith(prefix))
                self.assertGreater(len(word), len(prefix))


if __name__ == "__main__":
    unittest.main()
