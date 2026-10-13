# Frozen AuGenda V1 Store

- Source revision: `d7f059e`
- Store: `AuGendaV1.store`
- SHA-256: `2ca0c9baf8dfd8960e9cbad9b9566635b208d08531f8621b77cfc6d13c2e331b`
- Generator: the `AuGendaSchemaV1` application and model code from the source revision above
- Contents: deterministic, synthetic sentinel records for every V1 entity, scalar field, and modeled relationship
- Secrets and personal data: none
- SQLite integrity check at creation: `ok`

The fixture is deliberately checked in and treated as immutable. Migration
tests copy it to a temporary location before opening it so neither SwiftData
nor a failed test can mutate the source evidence.

The source revision was extracted with `git archive`. A test-only generator was
added outside the repository to insert the sentinel graph. To let that
historical iOS-first project execute its tests on macOS, its Watch embed phase
was excluded and one unavailable macOS list style was replaced in the temporary
copy. No model type, schema declaration, relationship, or generated store was
edited after creation.
