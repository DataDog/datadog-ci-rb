#!/usr/bin/env bash
# Install test for per-test line coverage. It installs datadog-ci from the tracked files of this checkout the ways
# a customer can, each case in new containers of a Ruby image, and checks how the native extension was built.
#
#   bash integration/line_coverage_install/run.sh OUTPUT_DIRECTORY [IMAGE...]
#
# IMAGE defaults to ruby:3.2-bookworm ruby:3.3-bookworm ruby:3.4-bookworm ruby:4.0-bookworm. The images run in
# parallel, the cases of one image one after another. Each case installs with access to rubygems.org, then runs
# probe.rb without network and judges its result with check.rb. DOCKER_RUN_OPTIONS adds options to every
# docker run. Prints one line per case and exits 1 when a case fails.
#
# Cases on every Ruby, which expect line coverage built with release headers of the running Ruby's minor version
# and the known answer:
#   gem-install     gem install of the gem built from this checkout, into an empty GEM_HOME.
#   bundle          a Gemfile with only datadog-ci, from a git repository of this checkout.
#   old-lock        a lock made without datadog-ci, then datadog-ci added to the Gemfile and a plain bundle
#                   install. On Ruby 4.0 the lock holds datadog 2.24.0 with datadog-ruby_core_source 3.4.3, which
#                   has only preview headers of Ruby 4.0. On older Rubies it holds datadog 2.4.0, which depends on
#                   another header gem.
# Cases of the build's own guard, which install datadog-ci without its dependencies next to an older
# datadog-ruby_core_source:
#   headers-3.4.2   Ruby 4.0: only ruby-4.0.0-preview2 headers. Expects no line coverage and an error at run time.
#   headers-3.4.3   Ruby 3.2 and 4.0: no release headers of that minor version. Expects the same.
#   headers-3.5.0   Ruby 4.0: ruby-4.0.0-p0, which that version's own lookup passes over for a preview. Expects
#                   line coverage built with ruby-4.0.0-p0.
#   no-header-gem   Ruby 3.3: datadog 2.4.0 and no datadog-ruby_core_source. Expects no line coverage and an
#                   error at run time.
set -uo pipefail

if [ $# -lt 1 ]; then
  echo "usage: bash $0 OUTPUT_DIRECTORY [IMAGE...]" >&2
  exit 2
fi
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
shift
IMAGES=("$@")
[ ${#IMAGES[@]} -gt 0 ] || IMAGES=(ruby:3.2-bookworm ruby:3.3-bookworm ruby:3.4-bookworm ruby:4.0-bookworm)
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)-$$
CASE_TIMEOUT=1800
KIT="$OUT/kit"
TOOLS=/kit/source/integration/line_coverage_install
GIT_GEM='gem "datadog-ci", git: "/kit/datadog-ci.git"'
BUILD='(cd /kit/source && gem build datadog-ci.gemspec --output /case/datadog-ci.gem)'
SUMMARY="$OUT/summary.txt"

cleanup() {
  docker ps -aq --filter "label=datadog-ci-install-test=$RUN_ID" | xargs -r docker rm -f > /dev/null
}
trap cleanup EXIT
trap 'jobs -p | xargs -r kill; exit 130' INT TERM

# The tracked files of the working tree, and a git repository of them for Bundler's git source.
rm -rf "$KIT"
mkdir -p "$KIT/source"
git -C "$REPO" ls-files -z | tar -C "$REPO" --null -T - -cf - | tar -C "$KIT/source" -xf - || exit 1
git -C "$KIT/source" init -q &&
  git -C "$KIT/source" add -A -f &&
  git -C "$KIT/source" -c user.name="install test" -c user.email=install-test@localhost -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null commit -q -m "working tree" &&
  git clone -q --bare "$KIT/source" "$KIT/datadog-ci.git" || exit 1
: > "$SUMMARY"

# run_in IMAGE CASE_DIRECTORY NETWORK COMMAND [NAME=VALUE...]
run_in() {
  local image=$1 directory=$2 network=$3 command=$4
  shift 4
  local environment=()
  for variable in "$@"; do environment+=(-e "$variable"); done
  # shellcheck disable=SC2086 # DOCKER_RUN_OPTIONS is a list of options.
  docker run --rm --init --network "$network" --user "$(id -u):$(id -g)" \
    --label "datadog-ci-install-test=$RUN_ID" ${DOCKER_RUN_OPTIONS:-} "${environment[@]}" \
    -e HOME=/case -e GEM_HOME=/case/gems -e BUNDLE_APP_CONFIG=/case/app/.bundle \
    -e PATH=/case/gems/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    -v "$KIT":/kit:ro -v "$directory":/case -w /case/app "$image" \
    timeout "$CASE_TIMEOUT" bash -c "$command"
}

# run_case IMAGE NAME INSTALL_COMMAND "bundle exec" or "" EXPECTED [DETAIL]
# The case's Gemfiles, if any, are in $GEMFILES as NAME=CONTENT lines.
run_case() {
  local image=$1 name=$2 install=$3 runner=$4 expected=$5 detail=${6:-}
  local directory="$OUT/cases/${image//[:\/]/-}-$name"
  rm -rf "$directory"
  mkdir -p "$directory/app"
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && printf '%b\n' "${line#*=}" > "$directory/app/${line%%=*}"
  done <<< "${GEMFILES:-}"
  run_in "$image" "$directory" bridge "$install" > "$directory/install.log" 2>&1
  local status=$? verdict
  if [ $status -ne 0 ]; then
    verdict="FAIL (install exited $status, see $directory/install.log)"
  else
    verdict=$(run_in "$image" "$directory" none \
      "$runner ruby $TOOLS/probe.rb /case/probe.json > /case/probe.log 2>&1; \
       ruby $TOOLS/check.rb /case/probe.json /case/probe.log \"\$EXPECTED\" \${DETAIL:+\"\$DETAIL\"}" \
      "EXPECTED=$expected" "DETAIL=$detail" 2>&1 | tail -1)
  fi
  printf '%-20s %-14s | %s\n' "$image" "$name" "$verdict" | tee -a "$SUMMARY"
}

run_image() {
  local image=$1 version minor
  version=$(docker run --rm --network none "$image" ruby -e 'print RUBY_VERSION') || {
    echo "$image: cannot run ruby" | tee -a "$SUMMARY"
    return
  }
  minor=${version%.*}
  local source='source "https://rubygems.org"'

  GEMFILES="" run_case "$image" gem-install \
    "$BUILD && gem install --no-document /case/datadog-ci.gem" "" lines

  GEMFILES="Gemfile=$source\n$GIT_GEM" run_case "$image" bundle \
    "bundle install --jobs 4" "bundle exec" lines

  local old_gems='gem "datadog", "2.4.0"'
  [ "$minor" = 4.0 ] && old_gems='gem "datadog", "2.24.0"\ngem "datadog-ruby_core_source", "3.4.3"'
  GEMFILES="Gemfile.old=$source\n$old_gems
Gemfile.new=$source\ngem \"datadog\"\n$GIT_GEM" run_case "$image" old-lock \
    "cp Gemfile.old Gemfile && bundle lock && cp Gemfile.lock Gemfile.lock.old && cp Gemfile.new Gemfile && \
     bundle install --jobs 4" "bundle exec" lines

  # datadog-ci without its dependencies, next to one version of datadog-ruby_core_source.
  local guard="gem install --no-document datadog -v 2.24.0 && \
    gem uninstall --all --ignore-dependencies datadog-ruby_core_source && \
    gem install --no-document --ignore-dependencies datadog-ruby_core_source -v HEADERS && \
    $BUILD && gem install --no-document --ignore-dependencies /case/datadog-ci.gem"
  if [ "$minor" = 4.0 ]; then
    GEMFILES="" run_case "$image" headers-3.4.2 "${guard/HEADERS/3.4.2}" "" none \
      "has no headers of a Ruby 4.0 release"
    GEMFILES="" run_case "$image" headers-3.5.0 "${guard/HEADERS/3.5.0}" "" lines ruby-4.0.0-p0
  fi
  if [ "$minor" = 4.0 ] || [ "$minor" = 3.2 ]; then
    GEMFILES="" run_case "$image" headers-3.4.3 "${guard/HEADERS/3.4.3}" "" none \
      "has no headers of a Ruby $minor release"
  fi
  if [ "$minor" = 3.3 ]; then
    GEMFILES="" run_case "$image" no-header-gem \
      "gem install --no-document datadog -v 2.4.0 && $BUILD && \
       gem install --no-document --ignore-dependencies /case/datadog-ci.gem" "" none \
      "the datadog-ruby_core_source gem could not be loaded"
  fi
}

for image in "${IMAGES[@]}"; do
  run_image "$image" > "$OUT/${image//[:\/]/-}.out" 2>&1 &
done
wait
sort "$SUMMARY" -o "$SUMMARY"
cat "$SUMMARY"
! grep -q "FAIL\|cannot run ruby" "$SUMMARY"
