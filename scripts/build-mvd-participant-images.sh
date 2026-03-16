#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <path-to-MinimumViableDataspace> <registry-prefix>" >&2
  exit 1
fi

mvd_root="$1"
registry_prefix="$2"

if [[ ! -d "$mvd_root" ]]; then
  echo "MVD path does not exist: $mvd_root" >&2
  exit 1
fi

if ! command -v java >/dev/null 2>&1; then
  echo "java is required" >&2
  exit 1
fi

if ! command -v javac >/dev/null 2>&1; then
  echo "javac is required. Install JDK 17." >&2
  exit 1
fi

if ! javac --version 2>/dev/null | grep -qE '^javac 17(\.|$)'; then
  echo "JDK 17 is required. Current javac: $(javac --version 2>/dev/null)" >&2
  exit 1
fi

if [[ -z "${JAVA_HOME:-}" && -d /usr/lib/jvm/java-17-openjdk-amd64 ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
  export PATH="$JAVA_HOME/bin:$PATH"
fi

cd "$mvd_root"

./gradlew --stop >/dev/null 2>&1 || true
./gradlew build
./gradlew -Ppersistence=true dockerize

for image in controlplane dataplane identity-hub; do
  target="${registry_prefix}/${image}:latest"
  docker tag "${image}:latest" "$target"
  docker push "$target"
done
