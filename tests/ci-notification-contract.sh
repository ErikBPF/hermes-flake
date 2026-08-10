#!/usr/bin/env bash
set -euo pipefail

workflow="$(git rev-parse --show-toplevel)/.github/workflows/build.yml"
grep -Fq 'needs: [build, flakehub-publish, flakehub-verify]' "$workflow"
grep -Fq "contains(needs.*.result, 'failure')" "$workflow"
