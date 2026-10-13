"""Live formatting checks using the application's actual Groq client and saved key."""
import json
import pathlib
import re
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parent.parent
binary = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / "release/Flow.app/Contents/MacOS/Flow"
cases = json.loads((root / "QA/formatting-cases.json").read_text())
results = []
prior = {}
if "--resume" in sys.argv and (root / "QA/formatting-results.json").exists():
    prior = {r["id"]: r for r in json.loads((root / "QA/formatting-results.json").read_text())["results"] if r["passed"]}
for case in cases:
    if case["id"] in prior:
        results.append(prior[case["id"]]); continue
    for attempt in range(3):
        run = subprocess.run([str(binary), "--format-transcript"], input=case["input"], text=True, capture_output=True, timeout=90)
        if run.returncode and "limiting requests" in run.stdout and attempt < 2:
            print(case["id"] + ": rate limited, retrying after 30 seconds", flush=True)
            time.sleep(30)
        else:
            break
    output = run.stdout.strip()
    failures = []
    if run.returncode:
        failures.append("API or client error")
    for word in case.get("required", []):
        if word.casefold() not in output.casefold():
            failures.append("Missing required wording: " + word)
    for word in case.get("forbidden", []):
        if word.casefold() in output.casefold():
            failures.append("Unresolved correction: " + word)
    numbered = re.findall(r"(?m)^\d+\. ", output)
    if "numbered" in case and len(numbered) != case["numbered"]:
        failures.append("Incorrect numbered-list structure")
    if case.get("prose") and (numbered or re.search(r"(?m)^[•*-] ", output)):
        failures.append("Unrequested list")
    if case.get("paragraphs") and "\n\n" not in output:
        failures.append("Missing paragraph break")
    if "max_words" in case and len(output.split()) > case["max_words"]:
        failures.append("Added prose or answered dictation")
    if any(marker in output for marker in ["—", "–", "```", "**", "<think>"]):
        failures.append("Unwanted punctuation or output wrapper")
    results.append({**case, "output": output, "passed": not failures, "failures": failures})
    print(case["id"] + ": " + ("PASS" if not failures else "FAIL " + "; ".join(failures)), flush=True)
    time.sleep(12)
report = {"passed": sum(r["passed"] for r in results), "total": len(results), "model": "openai/gpt-oss-120b", "results": results}
(root / "QA/formatting-results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"{report['passed']}/{report['total']} live formatting checks passed")
sys.exit(0 if report["passed"] == report["total"] else 1)
