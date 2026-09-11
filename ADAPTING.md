# Adapting Delegation Kit

Edit the personal configuration described in
[User configuration](docs/user-configuration.md), then run
`delegation-config validate` and `delegation-config apply`. Nothing else in the
kit has to change to make a new model executable.

Choose the adapter, actual requested model, roles and supported parameters.
For custom OpenAI-compatible endpoints supply `base_url` and optionally
`credential_env`, the name of an environment variable. Never store its value in
the profile. Models do not require kit qualification, benchmark thresholds or
provider-attested identity to be used.

The adapter owns capabilities. Adding `builder` to a text adapter produces a
textual patch; it cannot grant write access. Native adapters retain their
sandbox, tool restrictions and credential handling. Unsupported parameters
produce errors. Failed attempts do not authorize retries or fallback.

Review defaults to `optional`, including upgrades. Use `required` for any
compatible reviewer or `cross-family` for another declared family. `init
--preset strict` enables cross-family policy for a new configuration. Changing
an existing policy is an explicit edit to the personal file, which updates
preserve. Required review never authorizes another call on its own.

Benchmarks are useful when choosing a preset, and nothing more: the routing
policy in `model-routing.md` is advisory. The lead checks the output, applies
and tests patches, and reports model identity provenance accurately.
