# User-directed model routing

> This document is advisory reading. It governs nothing: no command reads it,
> and no status, benchmark, or table in it authorizes or blocks a dispatch.

`delegation-route` reads the personal configuration and the code-owned adapter
capabilities. Models do not require kit qualification.

Display `.choices`, obtain the user's explicit selection or permission to choose,
and validate it with `resolve --selected-profile`. Validation never dispatches
or grants authorization. Each retry, fallback, review or additional worker needs
its own explicit authorization. The default review policy is `optional`; users
may choose `required` or `cross-family`. Mandatory review does not authorize a call.

The integrating lead verifies outputs, tests patches and owns the final response.
See [configuration and migration](docs/user-configuration.md) for schemas,
provider examples, capabilities, identity provenance and review receipts.
