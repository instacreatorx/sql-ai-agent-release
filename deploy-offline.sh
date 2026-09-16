#!/usr/bin/env bash

# Remove conflicting Docker packages before installing Docker from the official repository.
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc | cut -f1)

# ----------------------------------------------------
# DOCKER INSTALLATION
# ----------------------------------------------------
# Add Docker's official GPG key:
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

# Install the Docker packages:
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify that Docker is running:
sudo systemctl status docker

# Strict configurations to capture errors instantly within our FSM
set -eo pipefail

TARGET_ZIP=$(ls app-delivery-*.zip 2>/dev/null | head -n 1)
TARGET_PORT=4000
CONTAINER_NAME="sql-ai-agent-onprem-app"

# ----------------------------------------------------
# ARGUMENT PARSER (NEW)
# ----------------------------------------------------
INIT_ADMIN_PASS=""

for arg in "$@"; do
  case $arg in
    --pass=*)
      INIT_ADMIN_PASS="${arg#*=}"
      ;;
  esac
done

if [[ -z "$INIT_ADMIN_PASS" ]]; then
  echo -e "\e[1;33m[WARN]\e[0m No admin password provided via --pass=..."
  echo "INIT_ADMIN_PASS will not be injected into container."
else
  export INIT_ADMIN_PASS
  echo -e "\e[1;32m[INFO]\e[0m INIT_ADMIN_PASS captured: $INIT_ADMIN_PASS"
fi

# FSM Transition Handlers
log_state() { echo -e "\e[1;34m[STATE-CHANGE]\e[0m Entering State: $1"; }
raise_error() { echo -e "\e[1;31m[FSM-FATAL CRASH ($1)]\e[0m $2"; exit "$1"; }

# ----------------------------------------------------
# S0: INIT STATE
# ----------------------------------------------------
log_state "S0: INIT"
if [[ -z "$TARGET_ZIP" ]]; then
    raise_error 1 "E1: Initialization failure. No delivery deployment ZIP target package was detected in working directory."
fi
echo "Located build asset package: $TARGET_ZIP"

# ----------------------------------------------------
# S1: EXTRACT STATE
# ----------------------------------------------------
log_state "S1: EXTRACT"
echo "Decompressing production archive configuration layer..."
if ! unzip -o "$TARGET_ZIP"; then
    raise_error 2 "E2: Corrupt archive matrix payload. Unzip command failed structural file extraction."
fi

if [[ ! -f "app-image.tar" ]]; then
    raise_error 2 "E2: Corrupt payload container. File app-image.tar was missing from inside extracted zip."
fi

# ----------------------------------------------------
# S2: LOADING STATE
# ----------------------------------------------------
log_state "S2: LOADING"
echo "Injecting image layers into offline Docker local engine context..."
LOAD_OUTPUT=$(docker load -i app-image.tar)
if [[ $? -ne 0 ]]; then
    raise_error 3 "E3: Docker local loading sequence failure. Incompatible CPU layout or context engine freeze."
fi

IMAGE_TAG=$(echo "$LOAD_OUTPUT" | awk '/Loaded image:/ {print $3}')
if [[ -z "$IMAGE_TAG" ]]; then
    raise_error 3 "E3: Image validation extraction failure. Unable to capture loaded image identifier tag."
fi
echo "Successfully loaded image reference: $IMAGE_TAG"

# ----------------------------------------------------
# S3: CLEANUP STATE
# ----------------------------------------------------
log_state "S3: CLEANUP"
echo "Pruning existing legacy running instances of application..."
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    docker rm -f "$CONTAINER_NAME" || echo "Warning (W1): Active runtime container block removal warning. Overriding system lock."
fi
docker image prune -f || echo "Warning (W1): Engine storage reclamation warning. Skipping layer cache purge step."

# ----------------------------------------------------
# S4: RUNNING STATE
# ----------------------------------------------------
log_state "S4: RUNNING"
echo "Booting container application inside isolated networking environment..."

# NEW: inject INIT_ADMIN_PASS into container
if ! docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${TARGET_PORT}:3000" \
    --restart always \
    -e INIT_ADMIN_PASS="$INIT_ADMIN_PASS" \
    "$IMAGE_TAG"; then
    raise_error 4 "E4: Runtime container execution failure. Address port configuration collision or runtime memory limit hit."
fi

# ----------------------------------------------------
# S5: HALT STATE (Verification)
# ----------------------------------------------------
log_state "S5: HALT"
echo "Verifying local service routing health integrity..."
sleep 3
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" = "true" ]; then
    echo -e "\n\e[1;32m[SUCCESS-HALT]\e[0m Application deployed. Listening on local port ${TARGET_PORT}."
    echo "Cleaning temporary runtime payload files..."
    rm -f app-image.tar
    exit 0
else
    raise_error 4 "E4: Post-boot instability. Container initialization failed or application crashed during entrypoint execution."
fi
