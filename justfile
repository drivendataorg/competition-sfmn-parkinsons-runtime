# Settings
set dotenv-load
block_internet := env_var_or_default("BLOCK_INTERNET", "true")
platform_args := "--platform linux/amd64"

tag := "gpu-latest"
local_tag := "gpu-local"

image_name := "competition-sfmn-parkinsons-runtime"
official_image := "competitionsfmnparkinsonsprodacr.azurecr.io/" + image_name
local_image := image_name

# Resolve which image to use
submission_image := env_var_or_default("SUBMISSION_IMAGE", local_image + ":" + local_tag)
container_name := env_var_or_default("CONTAINER_NAME", image_name)
data_dir := env_var_or_default("DATA_DIR", justfile_directory() + "/data-demo")


# Helper functions to detect GPU and TTY
_gpu_args := if `command -v nvidia-smi > /dev/null 2>&1 && echo "1" || echo ""` != "" { "--gpus all" } else { "" }
_tty_args := if env_var_or_default("GITHUB_ACTIONS_NO_TTY", "") != "true" { "-it" } else { "" }
_network_args := if block_internet == "true" { "--network none" } else { "" }

# Default recipe - show help
_default:
    @just --list

# Helper: Set write permissions on submission folder
_submission-write-perms:
    mkdir -p submission/
    chmod -R 0777 submission/

# Helper: Check if image exists
_check-image:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Checking submission image: {{submission_image}}"
    if [[ -z "$(docker images -q {{submission_image}} 2>/dev/null)" ]]; then
        echo "Error: No image found for {{submission_image}}"
        echo "Run 'just pull' and set SUBMISSION_IMAGE in .env (see README), or run 'just build'."
        exit 1
    fi

# Helper: Echo image information
_echo-image:
    #!/usr/bin/env bash
    set -euo pipefail
    echo
    SUBMISSION_IMAGE_ID=$(docker images -q {{submission_image}} 2>/dev/null || echo "")
    if [[ -z "$SUBMISSION_IMAGE_ID" ]]; then
        echo "$(tput bold)Using image:$(tput sgr0) {{submission_image}} (image does not exist locally)"
        echo
    else
        echo "$(tput bold)Using image:$(tput sgr0) {{submission_image}} ($SUBMISSION_IMAGE_ID)"
        echo "┏"
        echo "┃ NAME(S)"
        docker inspect $SUBMISSION_IMAGE_ID --format='{{{{join .RepoTags "\n"}}}}' | awk '{print "┃ "$0}'
        echo "└"
        echo
    fi

    if [[ -z "$(docker images {{official_image}} -q 2>/dev/null)" ]]; then
        echo "$(tput bold)No official images available locally$(tput sgr0)"
        echo "Run 'just pull' to download the official image."
        echo
    else
        echo "$(tput bold)Available official images:$(tput sgr0)"
        echo "┏"
        docker images {{official_image}} | awk '{print "┃ "$0}'
        echo "└"
        echo
    fi

    if [[ -z "$(docker images {{local_image}} -q 2>/dev/null)" ]]; then
        echo "$(tput bold)No local images available$(tput sgr0)"
        echo "Run 'just build' to build the image."
        echo
    else
        echo "$(tput bold)Available local images:$(tput sgr0)"
        echo "┏"
        docker images {{local_image}} | awk '{print "┃ "$0}'
        echo "└"
        echo
    fi

# Show image status and available commands
help: _echo-image
    @echo "$(tput bold)Available commands:$(tput sgr0)"
    @echo
    @just --list

# Print active variables for debugging
[group('development')]
debug:
    @echo "block_internet={{block_internet}}"
    @echo "submission_image={{submission_image}}"
    @echo "official_image={{official_image}}:{{tag}}"
    @echo "local_image={{local_image}}:{{local_tag}}"
    @echo "platform_args={{platform_args}}"
    @echo "_gpu_args={{_gpu_args}}"
    @echo "_network_args={{_network_args}}"
    @echo "data_dir={{data_dir}}"

# Build the runtime container
[group('development')]
build *ARGS:
    docker build runtime \
        {{platform_args}} \
        --target runtime \
        --tag {{local_image}}:{{local_tag}} \
        {{ARGS}}

# Build the test container
[group('tests')]
build-tests:
    docker build runtime \
        {{platform_args}} \
        --target test-runtime \
        --tag {{local_image}}:test

# Run tests in the test container
[group('tests')]
run-tests:
    docker run \
        {{platform_args}} \
        {{_gpu_args}} \
        {{_network_args}} \
        --rm \
        {{local_image}}:test

# Open an interactive bash shell in the test container
[group('tests')]
interact-tests:
    docker run -it \
        --rm \
        {{platform_args}} \
        {{_gpu_args}} \
        {{_network_args}} \
        {{local_image}}:test \
        bash

# Update uv lockfile
[group('development')]
update-lockfile *ARGS:
    cd runtime && uv lock {{ARGS}}

# Check that uv lockfile is in sync with pyproject.toml
[group('development')]
check-lock:
    cd runtime && uv lock --check

# Pull the official container from Azure Container Registry
[group('* test submission locally')]
pull:
    docker pull {{official_image}}:{{tag}}

[confirm("Are you sure you want to overwrite the existing submission/submission.zip file? (y/n)")]
_confirm_submission_overwrite:
    @echo "Overwriting existing submission/submission.zip file."
    rm -f submission/submission.zip

# Create submission.zip from examples folder (e.g., just pack-example minimal)
[group('* test submission locally')]
pack-example example_name:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -f ./submission/submission.zip ]]; then
        just _confirm_submission_overwrite
    fi
    mkdir -p submission/
    cd examples/{{example_name}} && uvx rpzip -r ../../submission/submission.zip ./*
    echo "Wrote submission/submission.zip based on source files in examples/{{example_name}}/"

# Create submission.zip from submission_src folder
[group('* test submission locally')]
pack-submission:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    files=(submission_src/*)
    if (( ${#files[@]} == 0 )); then
        echo "ERROR: submission_src/ directory is empty. Cannot create submission.zip with no files."
        exit 1
    fi
    if [[ -f ./submission/submission.zip ]]; then
        just _confirm_submission_overwrite
    fi
    mkdir -p submission/
    cd submission_src && uvx rpzip -r ../submission/submission.zip ./*
    echo "Wrote submission/submission.zip based on source files in submission_src/"

# Check contents of current submission.zip file
[group('* test submission locally')]
check-submission:
    #!/usr/bin/env bash
    set -euo pipefail
    unzip -l submission/submission.zip
    submission_files=$(unzip -Z1 submission/submission.zip)
    if ! grep -F -x -q -- "main.py" <<<"$submission_files"; then
        echo "ERROR: Submission ZIP archive must include main.py in the root directory."
        exit 1
    else
        echo "VALIDATION PASSED: Submission ZIP archive contains main.py."
    fi

# Test submission using submission.zip
[group('* test submission locally')]
test-submission: _check-image _echo-image _submission-write-perms
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f ./submission/submission.zip ]]; then
        echo "Error: submission/submission.zip not found. Run 'just pack-example' or 'just pack-submission' first."
        exit 1
    fi
    SUBMISSION_IMAGE_ID=$(docker images -q {{submission_image}})
    docker run \
        {{platform_args}} \
        {{_tty_args}} \
        {{_gpu_args}} \
        {{_network_args}} \
        -e LOGURU_LEVEL=INFO \
        -e IS_SMOKE_TEST="1" \
        --mount type=bind,source={{data_dir}},target=/code_execution/data,readonly \
        --mount type=bind,source="$(pwd)/submission",target=/code_execution/submission \
        --shm-size 8g \
        --pid host \
        --name {{container_name}} \
        --rm \
        $SUBMISSION_IMAGE_ID

# Open an interactive bash shell within the container
[group('* test submission locally')]
interact-container: _check-image _echo-image _submission-write-perms
    #!/usr/bin/env bash
    set -euo pipefail
    SUBMISSION_IMAGE_ID=$(docker images -q {{submission_image}})
    docker run \
        {{platform_args}} \
        {{_gpu_args}} \
        {{_network_args}} \
        --mount type=bind,source={{data_dir}},target=/code_execution/data,readonly \
        --mount type=bind,source="$(pwd)/submission",target=/code_execution/submission \
        --shm-size 8g \
        --pid host \
        -it \
        $SUBMISSION_IMAGE_ID \
        bash

# Delete temporary Python cache and bytecode files
[group('development')]
clean:
    find . -type f -name "*.py[co]" -delete
    find . -type d -name "__pycache__" -delete

# Format code with ruff
[group('development')]
format:
    uvx ruff format