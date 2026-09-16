#!/usr/bin/env bash
set -euo pipefail

SECRET="$1"

if [ -z "$SECRET" ]; then
    echo "Usage: $0 <webhook-secret>" >&2
    exit 1
fi

if [ -z "${HTTP_X_HUB_SIGNATURE_256:-}" ]; then
    echo "No signature header received. Rejecting." >&2
    exit 1
fi

PAYLOAD_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE"' EXIT

cat > "$PAYLOAD_FILE"

EXPECTED_SIG="${HTTP_X_HUB_SIGNATURE_256}"

if [[ ! "$EXPECTED_SIG" =~ ^sha256= ]]; then
    echo "Invalid signature format. Expected sha256= prefix." >&2
    exit 1
fi

EXPECTED_HEX="${EXPECTED_SIG#sha256=}"

COMPUTED_HEX=$(openssl dgst -sha256 -hmac "$SECRET" "$PAYLOAD_FILE" | awk '{print $NF}')

if [ "$EXPECTED_HEX" != "$COMPUTED_HEX" ]; then
    echo "Webhook signature mismatch. Request rejected." >&2
    exit 1
fi

echo "Webhook signature verified."
exit 0
