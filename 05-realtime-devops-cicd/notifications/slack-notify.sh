#!/usr/bin/env bash
set -euo pipefail

STATUS="$1"
WEBHOOK_URL="$2"
CHANNEL="$3"
APP_NAME="$4"
BUILD_VERSION="$5"
DEPLOY_ENV="$6"
BUILD_URL="$7"

case "$STATUS" in
    started)
        EMOJI=":rocket:"
        TITLE="Pipeline Started"
        COLOR="#439FE0"
        ;;
    success)
        EMOJI=":white_check_mark:"
        TITLE="Pipeline Passed"
        COLOR="#36A64F"
        ;;
    failure)
        EMOJI=":x:"
        TITLE="Pipeline Failed"
        COLOR="#FF0000"
        ;;
    aborted)
        EMOJI=":no_entry_sign:"
        TITLE="Pipeline Aborted"
        COLOR="#FFA500"
        ;;
    *)
        EMOJI=":grey_question:"
        TITLE="Pipeline Unknown"
        COLOR="#808080"
        ;;
esac

if [ "$DEPLOY_ENV" != "none" ]; then
    DEPLOY_LINE="Deployed to *${DEPLOY_ENV}*"
else
    DEPLOY_LINE="Build only (no deploy)"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PAYLOAD=$(cat <<EOF
{
    "channel": "${CHANNEL}",
    "username": "CI/CD Bot",
    "icon_emoji": ":gear:",
    "attachments": [
        {
            "color": "${COLOR}",
            "blocks": [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": "${EMOJI} ${TITLE}"
                    }
                },
                {
                    "type": "section",
                    "fields": [
                        {
                            "type": "mrkdwn",
                            "text": "*App:*\n${APP_NAME}"
                        },
                        {
                            "type": "mrkdwn",
                            "text": "*Version:*\n${BUILD_VERSION}"
                        },
                        {
                            "type": "mrkdwn",
                            "text": "*Environment:*\n${DEPLOY_ENV}"
                        },
                        {
                            "type": "mrkdwn",
                            "text": "*Status:*\n${STATUS}"
                        }
                    ]
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "${DEPLOY_LINE}"
                    }
                },
                {
                    "type": "context",
                    "elements": [
                        {
                            "type": "mrkdwn",
                            "text": "Build: <${BUILD_URL}|#${BUILD_VERSION}> | ${TIMESTAMP}"
                        }
                    ]
                }
            ]
        }
    ]
}
EOF
)

curl -s -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL" > /dev/null

echo "Slack notification sent."
