#!/bin/sh
set -eu
cd "$(dirname "$0")/.." || exit 1

if [ "$#" -gt 1 ] || [ "${1:-mutineer}" != mutineer ]; then
  echo "Usage: sh bin/mutation.sh [mutineer]" >&2
  exit 2
fi

mkdir -p tmp/mutation

# A broken baseline must never look like successfully killed mutations.
bundle exec rspec spec/datadog/ci/git/changed_lines_spec.rb \
  spec/datadog/ci/git/changed_lines_property_spec.rb --seed 20260918 --format progress

exec bundle exec mutineer run lib/datadog/ci/git/changed_lines.rb \
  --test spec/datadog/ci/git/changed_lines_spec.rb \
  --test spec/datadog/ci/git/changed_lines_property_spec.rb \
  --framework rspec --jobs 2 --threshold 100 \
  --format json --output tmp/mutation/mutineer.json
