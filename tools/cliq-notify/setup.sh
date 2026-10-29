#!/bin/bash
# Creates the config and secrets files for the Multica -> Cliq relay. Safe to re-run. Never prints secrets.
#   bash setup.sh            create the folders and templates (does not overwrite existing files)
#   bash setup.sh --launchd  also write the launchd plist to ~/Library/LaunchAgents (does NOT load it)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CONF="$HOME/.config/multica-cliq"; STATE="$HOME/.local/state/multica-cliq"
mkdir -p "$CONF" "$STATE"; chmod 700 "$CONF" "$STATE"
if [ ! -f "$CONF/secrets.env" ]; then
	cat > "$CONF/secrets.env" <<'ENV'
# Zoho Cliq settings for the Multica -> Cliq relay. Keep this file private (mode 600). Never commit it.
# OPTION A (simplest): the bot's incoming webhook / message endpoint URL, including its key.
#   Cliq: Bots & Tools > Bots > your bot > (Incoming Webhook handler) > copy the endpoint URL
CLIQ_ENDPOINT=https://cliq.zoho.in/api/v2/bots/kboto/message
# OPTION B (OAuth): use when you only have the bot unique name and an OAuth client. Leave CLIQ_ENDPOINT empty.
# CLIQ_BOT=yourbotuniquename
# CLIQ_CLIENT_ID=
# CLIQ_CLIENT_SECRET=
# CLIQ_REFRESH_TOKEN=
# CLIQ_ACCOUNTS=https://accounts.zoho.in     # your Zoho accounts domain (.in for India, .eu for Europe)
# CLIQ_API=https://cliq.zoho.in              # your Cliq domain (.in, .eu ...)
# Deliver to specific bot subscribers (comma separated Cliq user ids or emails). Usually leave empty: the bot messages its subscribers, i.e. you.
# CLIQ_USER_IDS=
# Optional: a dedicated Multica token (otherwise the relay reads your Multica CLI login at run time)
# MULTICA_TOKEN=
ENV
	echo "created $CONF/secrets.env"
fi
chmod 600 "$CONF/secrets.env"
if [ ! -f "$CONF/config.json" ]; then
	cat > "$CONF/config.json" <<'JSON'
{
  "types": ["mentioned"],
  "snippet_chars": 400,
  "poll_minutes": 5,
  "catchup_max_age_hours": 24
}
JSON
	echo "created $CONF/config.json"
fi
NODE="$(command -v node || true)"; [ -n "$NODE" ] || { echo "node not found (need Node 22 or newer)"; exit 1; }
echo "node: $NODE ($($NODE --version))"
if [ "${1:-}" = "--launchd" ]; then
	mkdir -p "$HOME/Library/LaunchAgents"
	PL="$HOME/Library/LaunchAgents/com.balaji.multica-cliq.plist"
	cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.balaji.multica-cliq</string>
  <key>ProgramArguments</key><array><string>$NODE</string><string>$HERE/relay.mjs</string></array>
  <key>WorkingDirectory</key><string>$HERE</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardOutPath</key><string>$STATE/relay.log</string>
  <key>StandardErrorPath</key><string>$STATE/relay.err.log</string>
</dict></plist>
PLIST
	chmod 644 "$PL"; plutil -lint "$PL"
	echo "wrote $PL (not loaded). Start it with:  launchctl bootstrap gui/$(id -u) $PL"
	echo "Stop it with:                          launchctl bootout gui/$(id -u) $PL"
fi
echo "next: edit $CONF/secrets.env, then:  node $HERE/relay.mjs --check"
