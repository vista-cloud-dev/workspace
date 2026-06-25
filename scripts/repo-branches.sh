#!/usr/bin/env bash
# Shared map: repos whose active work lives on a branch other than the default.
# Single source of truth — sourced by ../bootstrap.sh and ./git-update-all-repos.
# Keep entries in sync with reality; an empty map means "everything on default".
# shellcheck disable=SC2034
declare -A BRANCH_OVERRIDES=(
  [vista-iris]="feat/container-build-scaffold"
  [m-stdlib]="iris-native-backends"
)
