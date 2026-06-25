#!/usr/bin/env bash
# Shared map: repos whose active work lives on a branch other than the default.
# Single source of truth — sourced by ../bootstrap.sh and ./git-update-all-repos.
# Keep entries in sync with reality; an empty map means "everything on default".
# shellcheck disable=SC2034
declare -A BRANCH_OVERRIDES=(
  # (empty) — all repos currently track their default branch.
  # Past entries retired once their feature work merged & the branch was deleted:
  #   vista-iris=feat/container-build-scaffold  (merged PR #2)
  #   m-stdlib=iris-native-backends             (IRIS backend work landed on master)
)
