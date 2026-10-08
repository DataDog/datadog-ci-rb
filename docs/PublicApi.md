# Public API

`datadog-ci` respects [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

Classes, modules, and methods marked as part of the public API will not introduce
breaking changes outside of a major version release.

Objects that belong to the public API are marked with the `@public_api` YARD documentation tag.
When navigating [`datadog-ci`'s YARD documentation](https://rubydoc.info/gems/datadog-ci), public API
objects will have an explicit banner informing the user that they are part of the public API contract.

Objects not marked with the `@public_api` tag are not part of the public API contract, and thus
considered internal to `datadog-ci`. These objects can receive breaking changes in minor and patch
releases.

## SDK-owned metadata

The generic tagging methods (`set_tag`, `set_tags`, `clear_tag`, and `set_metric`)
accept custom fields. SDK-owned fields are read-only through these methods,
including Git and CI metadata, test identity and status, runtime information,
feature flags, correlation IDs, and SDK metrics. Rejected mutations leave the
value unchanged and log an error once per field and operation per process.
The supplied value is not included in the error.

Use the supported APIs to change test state: `passed!`, `failed!`, `skipped!`,
`set_parameters`, and `itr_unskippable!`. Configure Git metadata through the
supported `DD_GIT_*` environment variables before starting the test session.

Manual instrumentation can still provide framework, framework version, test type,
source location, codeowners, and parameters in creation-time `tags:`. Other
SDK-owned fields in that input are ignored. Custom names such as `test.owner`,
`ci.custom`, and `git.custom` remain writable; protection matches specific SDK
fields rather than entire prefixes.

Read metadata through the CI span's `get_tag` and convenience methods such as
`git_branch`. Shared Git/CI defaults live in the test tracing context and are
sent once in payload metadata for tests, suites, modules, and sessions. They are
not copied into each underlying tracer span. Ordinary CI custom spans continue
to carry their own metadata because the intake does not apply test-level defaults
to them. Directly mutating the underlying tracer span is outside the CI tagging
API and is not covered by its mutation diagnostics.
