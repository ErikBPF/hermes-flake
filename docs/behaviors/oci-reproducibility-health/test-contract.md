# OCI reproducibility and health test contract

**Seed:** `behavior.md`

## OCI module

- Evaluate `services.hermes-agent-oci.enableHealthcheck = true`.
- Assert `hermes-agent-healthcheck.service` and its timer exist.
- Assert the probe URL uses the OCI module's configured API host and port.
- Keep the existing official-image and volume assertions green.

## Discovery consumer

- Assert the configured image is an immutable
  `nousresearch/hermes-agent@sha256:<64 hex characters>` reference.

## Gates

- Red: OCI module check fails because the health-check units are absent.
- Green: targeted OCI check, formatting, lint, and package build pass.
- Consumer: `just lint && just fmt-check`, then `just dry discovery`.
