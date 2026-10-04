"""Reject false cold-launch success from tabs, login screens, or broken OCR."""
import csv
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from verify_home_frame import home_evidence, verify_models


def framebuffer_tsv(lines, dimensions=(1206, 2622), confidence=96):
    out = io.StringIO()
    writer = csv.writer(out, delimiter="\t")
    writer.writerow(["level", "page_num", "block_num", "par_num", "line_num", "word_num",
                     "left", "top", "width", "height", "conf", "text"])
    writer.writerow([1, 1, 0, 0, 0, 0, 0, 0, *dimensions, -1, ""])
    for block, (text, top) in enumerate(lines, 1):
        for word_num, word in enumerate(text.split(), 1):
            writer.writerow([5, 1, block, 1, 1, word_num, word_num * 50,
                             top, 40, 35, confidence, word])
    return out.getvalue()


class HomeFrameChecks(unittest.TestCase):
    headers = [("Главная", 384), ("Нашиды без музыки", 538)]

    def test_visible_header_has_pixel_evidence(self):
        result = home_evidence(framebuffer_tsv(self.headers), 1206, 2622)
        self.assertEqual(result["header"]["title"]["top"], 384)
        self.assertEqual(result["header"]["subtitle"]["normalized"], "нашиды без музыки")

    def test_bottom_home_tab_does_not_establish_home(self):
        profile = [("Профиль", 384), ("Нашиды без музыки", 538), ("Главная", 2510)]
        with self.assertRaises(AssertionError):
            home_evidence(framebuffer_tsv(profile), 1206, 2622)

    def test_guest_login_and_spinner_remain_failures(self):
        for blocked in ("Гостевой режим", "Войти или создать аккаунт", "Открываем Muwa..."):
            with self.subTest(blocked=blocked), self.assertRaises(AssertionError):
                home_evidence(framebuffer_tsv([*self.headers, (blocked, 900)]), 1206, 2622)

    def test_low_confidence_headers_are_not_success(self):
        with self.assertRaises(AssertionError):
            home_evidence(framebuffer_tsv(self.headers, confidence=42), 1206, 2622)

    def test_missing_and_reversed_headers_are_not_success(self):
        for lines in ([], self.headers[:1], [("Главная", 538), ("Нашиды без музыки", 384)]):
            with self.subTest(lines=lines), self.assertRaises(AssertionError):
                home_evidence(framebuffer_tsv(lines), 1206, 2622)

    def test_mismatched_framebuffer_dimensions_are_rejected(self):
        with self.assertRaises(AssertionError):
            home_evidence(framebuffer_tsv(self.headers, dimensions=(1080, 2400)), 1206, 2622)

    def test_invalid_ocr_confidence_is_rejected(self):
        for confidence in ("nan", "inf", -1, 101):
            with self.subTest(confidence=confidence), self.assertRaises(AssertionError):
                home_evidence(framebuffer_tsv(self.headers, confidence=confidence), 1206, 2622)

    def test_diagnostics_cannot_become_ocr_pixels(self):
        with self.assertRaises(AssertionError):
            home_evidence("tesseract failed: Главная Нашиды без музыки", 1206, 2622)

    def test_altered_or_missing_language_models_are_rejected(self):
        expected = hashlib.sha256(b"verified model").hexdigest()
        with tempfile.TemporaryDirectory() as temporary, patch(
                "verify_home_frame.MODEL_HASHES", {"rus": expected}):
            path = Path(temporary) / "rus.traineddata"
            with self.assertRaises(AssertionError):
                verify_models(Path(temporary))
            path.write_bytes(b"verified model")
            self.assertEqual(verify_models(Path(temporary))["rus"]["sha256"], expected)
            path.write_bytes(b"altered model")
            with self.assertRaises(AssertionError):
                verify_models(Path(temporary))


if __name__ == "__main__":
    unittest.main()
