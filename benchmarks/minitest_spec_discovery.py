"""Fresh-process, randomized paired comparisons; uses only Python's standard library.

Example (from the checkout, with bundle dependencies already installed):
  python3 benchmarks/minitest_spec_discovery.py --ruby /path/to/ruby \
    --gemfile /path/to/gemfiles/ruby_3.4_minitest_5.gemfile \
    --output /private/tmp/minitest-discovery-benchmark

The candidate is a snapshot of the working tree's lib directory, preserving edits.
No production monkey patches are used. Runtime and allocation results include GC.
"""
import argparse
import hashlib
import io
import itertools
import json
import math
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import tarfile
import time
import os


def fixtures(root, workload):
    root.mkdir(parents=True, exist_ok=True)
    (root / "support.rb").write_text('''module BenchmarkFixtures
  class << self
    attr_accessor :executions
  end
  self.executions = 0
end
''')
    with (root / "support.rb").open("a") as support:
        for level in range(8):
            support.write(f'''module BenchmarkFixtures::SharedTests{level}
  def test_shared_{level}
    BenchmarkFixtures.executions += 1
    assert_equal 6, [1, 2, 3].sum
  end
end
''')
    groups, depth, tests_per_class = (40, 2, 4) if workload == "mixed" else (200, 8, 2)
    classes = tests = 0
    for group in range(groups):
        lines = []
        for level in range(depth):
            lines += [f'describe "Group{group}Level{level}" do',
                      f'include BenchmarkFixtures::SharedTests{level}']
            for test in range(tests_per_class - 1):
                lines += [f'it("test {test}") do',
                          'BenchmarkFixtures.executions += 1',
                          'assert_equal({a: 1}, JSON.parse(\'{"a":1}\', symbolize_names: true))',
                          'end']
        lines += ['end'] * depth
        (root / f"group_{group:04}_test.rb").write_text("\n".join(lines) + "\n")
        classes += depth
        tests += depth * tests_per_class
    if workload == "mixed":
        for group in range(20):
            for kind, parent in [("Unit", "Minitest::Test"), ("Spec", "Minitest::Spec")]:
                (root / f"named_{kind}_{group}_test.rb").write_text(
                    f'class Named{kind}{group} < {parent}\n'
                    'include BenchmarkFixtures::SharedTests0\nend\n')
                classes += 1
                tests += 1
    (root / "counts.json").write_text(json.dumps({"classes": classes, "tests": tests}))


def snapshot(repo, revision, destination):
    if revision == "working-tree":
        shutil.copytree(repo / "lib", destination / "lib")
    else:
        archive = subprocess.check_output(["git", "archive", revision, "lib"], cwd=repo)
        destination.mkdir(parents=True)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(destination, filter="data")
    for native in (repo / "lib").glob("*.bundle"):
        shutil.copy2(native, destination / "lib" / native.name)
    for native in (repo / "lib").glob("*.so"):
        shutil.copy2(native, destination / "lib" / native.name)


def comparison(rows, baseline, metric, rng):
    logs = [math.log(row["candidate"][metric] / row[baseline][metric]) for row in rows]
    n = len(logs)
    boot = sorted(statistics.mean(rng.choices(logs, k=n)) for _ in range(10000))
    effect = lambda value: 100 * math.expm1(value)
    low, high = effect(boot[249]), effect(boot[9749])
    margin = 2 if "allocations" in metric else 5
    return {"baseline_mean": statistics.mean(row[baseline][metric] for row in rows),
            "candidate_mean": statistics.mean(row["candidate"][metric] for row in rows),
            "paired_change_percent": effect(statistics.mean(logs)),
            "ci95_percent": [low, high], "regression_margin_percent": margin,
            "assessment": "regression" if low > margin else
                "within_regression_margin" if high < margin else "inconclusive"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ruby", required=True)
    parser.add_argument("--gemfile", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--warmup", type=int, default=2)
    parser.add_argument("--seed", type=int, default=687)
    parser.add_argument("--base", default="8680fe67cf29f44db307575f77b7cc8ecb3e89d6")
    parser.add_argument("--reviewed", default="c740ccb50")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    variants = {"base": args.base, "reviewed": args.reviewed, "candidate": "working-tree"}
    for name, revision in variants.items():
        snapshot(repo, revision, output / name)
    for workload in ("mixed", "nested"):
        fixtures(output / "fixtures" / workload, workload)
    metadata = dict(vars(args), margins={"wall_percent": 5, "allocations_percent": 2},
                    method="paired log ratios, 10000 paired bootstrap resamples, percentile 95% CI",
                    candidate_diff=subprocess.check_output(["git", "diff", "--", "lib"], cwd=repo, text=True),
                    revisions={name: subprocess.check_output(["git", "rev-parse", rev], cwd=repo, text=True).strip()
                               for name, rev in variants.items() if rev != "working-tree"})
    metadata["harness_sha256"] = hashlib.sha256((repo / "benchmarks/minitest_spec_discovery.rb").read_bytes()).hexdigest()
    (output / "protocol.json").write_text(json.dumps(metadata, indent=2))
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("DD_", "BUNDLE_", "RUBY", "MT_", "COVERAGE"))}
    environment.update(BUNDLE_GEMFILE=str(Path(args.gemfile).resolve()),
                       DD_GIT_REPOSITORY_URL="https://example.com/benchmark.git", DD_GIT_COMMIT_SHA="1" * 40)
    cells = list(itertools.product(("mixed", "nested"), ("execution", "discovery")))
    rng = random.Random(args.seed)
    samples = {f"{w}/{m}": [] for w, m in cells}
    all_rows = []
    for block in range(-args.warmup, args.samples):
        rng.shuffle(cells)
        for workload, mode in cells:
            names = list(variants)
            rng.shuffle(names)
            paired = {}
            for variant in names:
                run_dir = output / "runs" / f"{block}_{workload}_{mode}_{variant}"
                run_dir.mkdir(parents=True)
                cache = run_dir / ".testoptimization"
                (cache / "cache/http").mkdir(parents=True)
                (cache / "manifest.txt").write_text("1")
                (cache / "cache/http/settings.json").write_text("{}")
                fixture_dir = run_dir / "fixtures"
                fixture_dir.symlink_to(output / "fixtures" / workload, target_is_directory=True)
                command = [args.ruby, "-rbundler/setup", str(repo / "benchmarks/minitest_spec_discovery.rb"),
                           str(output / variant), mode, str(fixture_dir),
                           str(run_dir / "result.json")]
                started = time.perf_counter()
                with (run_dir / "process.log").open("w") as log:
                    subprocess.run(command, cwd=run_dir, env=environment, stdout=log,
                                   stderr=subprocess.STDOUT, check=True, timeout=120)
                row = json.loads((run_dir / "result.json").read_text())
                row["process_seconds"] = time.perf_counter() - started
                paired[variant] = row
                all_rows.append(dict(block=block, workload=workload, mode=mode, variant=variant, **row))
            if block >= 0:
                samples[f"{workload}/{mode}"].append(paired)
        (output / "raw.json").write_text(json.dumps(all_rows, indent=2))
        print(f"Completed block {block + 1}/{args.samples}", flush=True)
    metrics = ["definition_seconds", "total_seconds", "process_seconds", "definition_allocations", "total_allocations"]
    results = {cell: {baseline: {metric: comparison(rows, baseline, metric, rng) for metric in metrics}
                      for baseline in ("base", "reviewed")} for cell, rows in samples.items()}
    (output / "summary.json").write_text(json.dumps(results, indent=2))
    print(json.dumps(results, indent=2), flush=True)


if __name__ == "__main__":
    main()
