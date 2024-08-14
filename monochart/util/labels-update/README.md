# Spoton-Monochart Label Update Tools

## Overview of tools

### `check-if-already-updated.bash`

This utility script simply checks if a pod deployment's labels have already been updated. It is
intended to be run from a deployment pipeline.

### `spoton-monochart-labels-updater.bash`

This is the tool that makes the changes. It creates a new deployment containing the updated labels.
It is intended to be run in a deployment pipeline. Here are the steps it performs:

1. Create a temporary deployment identical to the existing one except for the name.
2. Remove the old deployment.
3. Create a new deployment (with the original name) which contains the updated labels.
4. Remove the temporary deployment.
