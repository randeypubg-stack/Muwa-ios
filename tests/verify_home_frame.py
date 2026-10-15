"""Verify an unmodified native Home framebuffer with reproducible CPU OCR.

Only the CI host needs Tesseract. Language models come from the official
tessdata_best repository at an immutable commit and are verified before use.
Neither this verifier nor its models ship in the native application.
"""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import urllib.request


MODEL_COMMIT = "e12c65a915945e4c28e237a9b52bc4a8f39a0cec"
MODEL_HASHES = {
    "rus": "b617eb6830ffabaaa795dd87ea7fd251adfe9cf0efe05eb9a2e8128b7728d6b6",
    "eng": "8280aed0782fe27257a68ea10fe7ef324ca0f8d85bd2fd145d1c2b560bcb66ba",
}
MODEL_DIRECTORY = Path("build/home-ocr-models")
MIN_CONFIDENCE = 60.0


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_models(folder, prepare=False):
    folder.mkdir(parents=True, exist_ok=True)
    verified = {}
    for language, expected in MODEL_HASHES.items():
        path = folder / f"{language}.traineddata"
        if not path.exists() and prepare:
            url = ("https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/"
                   f"{MODEL_COMMIT}/{language}.traineddata")
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read()
            actual = hashlib.sha256(data).hexdigest()
            if actual != expected:
                raise AssertionError(f"Downloaded {language} model has an unexpected SHA-256")
            temporary = path.with_suffix(".download")
            temporary.write_bytes(data)
            temporary.replace(path)
        if not path.is_file() or digest(path) != expected:
            raise AssertionError(f"Missing or altered OCR model: {path}; prepare models before capture")
        verified[language] = {"sha256": expected, "bytes": path.stat().st_size}
    return verified


def png_dimensions(path):
    header = path.read_bytes()[:24]
    if len(header) != 24 or not header.startswith(b"\x89PNG\r\n\x1a\n"):
        raise AssertionError("Expected an unmodified native PNG framebuffer")
    width, height = struct.unpack(">II", header[16:24])
    if min(width, height) < 100:
        raise AssertionError(f"Native framebuffer is too small: {width}x{height}")
    return width, height


def normalized(text):
    return " ".join(re.findall(r"\w+", text.casefold()))


def home_evidence(tsv, width, height):
    """Require actual Home header pixels; a bottom tab label is insufficient."""
    reader = csv.DictReader(io.StringIO(tsv), delimiter="\t")
    required = {"level", "page_num", "block_num", "par_num", "line_num",
                "left", "top", "width", "height", "conf", "text"}
    if not required.issubset(reader.fieldnames or []):
        raise AssertionError("OCR did not return a valid TSV framebuffer result")
    lines = {}
    page_found = False
    for row in reader:
        if row["level"] == "1":
            if int(row["width"]) != width or int(row["height"]) != height:
                raise AssertionError("OCR page dimensions do not match the native PNG")
            page_found = True
        text = (row["text"] or "").strip()
        if row["level"] != "5" or not text:
            continue
        key = tuple(row[name] for name in ("page_num", "block_num", "par_num", "line_num"))
        word = {"text": text, "confidence": float(row["conf"]),
                "left": int(row["left"]), "top": int(row["top"]),
                "width": int(row["width"]), "height": int(row["height"])}
        if not 0 <= word["confidence"] <= 100:
            raise AssertionError("OCR returned an invalid confidence")
        if (word["left"] < 0 or word["top"] < 0 or word["width"] <= 0 or word["height"] <= 0 or
                word["left"] + word["width"] > width or
                word["top"] + word["height"] > height):
            raise AssertionError("OCR returned text outside the native framebuffer")
        lines.setdefault(key, []).append(word)
    if not page_found:
        raise AssertionError("OCR did not identify the native framebuffer page")
    recognized = []
    for words in lines.values():
        text = " ".join(word["text"] for word in words)
        recognized.append({"text": text, "normalized": normalized(text),
                           "top": min(word["top"] for word in words),
                           "bottom": max(word["top"] + word["height"] for word in words),
                           "minimumConfidence": min(word["confidence"] for word in words)})
    all_text = " ".join(line["normalized"] for line in recognized)
    for blocked in ("открываем muwa", "войти или создать аккаунт", "гостевой режим"):
        if blocked in all_text:
            raise AssertionError(f"The native frame still shows a loading/account screen: {blocked}")
    headers = {line["normalized"]: line for line in recognized
               if line["bottom"] <= height * 0.35 and
               line["minimumConfidence"] >= MIN_CONFIDENCE}
    title = headers.get("главная")
    subtitle = headers.get("нашиды без музыки")
    if title is None or subtitle is None or title["bottom"] >= subtitle["top"]:
        raise AssertionError("The native Home title and subtitle were not confidently visible at the top")
    return {"lines": [line["text"] for line in recognized],
            "header": {"title": title, "subtitle": subtitle}}


def verify_frame(path, model_folder, output_folder):
    width, height = png_dimensions(path)
    models = verify_models(model_folder)
    executable = shutil.which("tesseract")
    if executable is None:
        raise RuntimeError("Tesseract is not installed on this verification host")
    version = subprocess.check_output([executable, "--version"], text=True,
                                      stderr=subprocess.STDOUT, timeout=15)
    if not re.match(r"tesseract [5-9]\.", version):
        raise RuntimeError(f"This verifier requires Tesseract 5 or newer: {version}")
    output_folder.mkdir(parents=True, exist_ok=True)
    command = [executable, str(path.resolve()), "stdout", "--tessdata-dir",
               str(model_folder.resolve()), "-l", "rus+eng", "--oem", "1", "--psm", "11",
               "-c", "tessedit_create_tsv=1", "-c", "tessedit_create_txt=0"]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=60,
                            env={**os.environ, "OMP_THREAD_LIMIT": "1"})
    (output_folder / "recognition.tsv").write_text(result.stdout)
    (output_folder / "recognition.log").write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f"CPU OCR exited with {result.returncode}: {result.stderr}")
    proof = {"homeVisible": True, "width": width, "height": height,
             "sourcePNG": path.name, "sourceSHA256": digest(path),
             "recognitionEngine": "Tesseract", "computeDevice": "cpu",
             "engineVersion": version.splitlines()[0], "engineExecutable": executable,
             "modelRepository": "https://github.com/tesseract-ocr/tessdata_best",
             "modelCommit": MODEL_COMMIT, "models": models,
             **home_evidence(result.stdout, width, height)}
    (output_folder / "proof.json").write_text(json.dumps(proof, ensure_ascii=False, indent=2))
    return proof


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("png", nargs="?", type=Path)
    parser.add_argument("--prepare-models", action="store_true")
    parser.add_argument("--models", type=Path, default=MODEL_DIRECTORY)
    parser.add_argument("--output", type=Path, default=Path("build/previews/launch/ocr"))
    args = parser.parse_args()
    try:
        if args.prepare_models:
            proof = {"modelCommit": MODEL_COMMIT, "models": verify_models(args.models, prepare=True)}
        elif args.png is not None:
            proof = verify_frame(args.png, args.models, args.output)
        else:
            parser.error("Provide a native PNG, or prepare its pinned OCR models")
        print(json.dumps(proof, ensure_ascii=False, sort_keys=True))
    except Exception as error:
        print(json.dumps({"homeVisible": False, "errorType": type(error).__name__,
                          "errorMessage": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
