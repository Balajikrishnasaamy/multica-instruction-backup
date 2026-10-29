# Multica -> Zoho Cliq: notify me when I am @mentioned

What it does: a small program on this Mac listens to Multica (the same live `inbox:new` push the desktop app uses) and sends one Cliq message through your bot whenever a Multica comment @mentions you. It ignores everything else (comments, status changes, assignments). Nothing is written to Multica.

Message format (example). There is no web link: multica.ai is not reachable from this network, and the desktop app has no link that opens an issue. Search the identifier in the Multica desktop app.
```
*Classify & Route* mentioned you on *CIRD-27*: List sorted by a field comes back unsorted ...

<first 400 characters of the comment, mention links turned into @names, secrets masked>

Issue: CIRD-27   (search this in the Multica app)
```

## Setup (about 10 minutes, you do steps 1 to 3)

1. **Create the files:** `bash ~/multica-instruction-backup/tools/cliq-notify/setup.sh`
   This creates `~/.config/multica-cliq/secrets.env` (mode 600) and `config.json`. Nothing else is touched.

2. **Create the Cliq bot** (Cliq > Bots & Tools > Bots > Create Bot):
   - Name it, for example "Multica". Unique name is shown on the bot's page.
   - Subscribe yourself to the bot (open the bot's permalink `https://cliq.zoho.com/bots/<unique_name>` and press Subscribe; use `.in` if your Cliq is on the India domain).
   - Use the bot message endpoint `https://cliq.zoho.in/api/v2/bots/<unique_name>/message` (use `.com` if your Cliq is on that domain). The copied URL does NOT contain the key.
   - The key is a separate **Webhook Token**: Cliq > Bots & Tools > Webhook Tokens (needs 2FA, 15 min session) > Generate New Token.

3. **Put the secret in the secrets file** (never in chat, never in the git repo):
   - Simple route (this is the one in use): paste the endpoint URL after `CLIQ_ENDPOINT=` and the Webhook Token after `CLIQ_WEBHOOK_TOKEN=` in `~/.config/multica-cliq/secrets.env`. The relay appends it as `?zapikey=`. Add the line by hand if your file lacks it.
   - OAuth route (not used here: Zoho answered `oauth_app_blocked`, cause unknown): fill `CLIQ_BOT`, `CLIQ_CLIENT_ID`, `CLIQ_CLIENT_SECRET`, `CLIQ_REFRESH_TOKEN` (scope `ZohoCliq.Webhooks.CREATE`) and the two domain lines for your region.

4. **Check, then test** (I can do these with you):
   ```
   node ~/multica-instruction-backup/tools/cliq-notify/relay.mjs --check        # login + settings, sends nothing
   node ~/multica-instruction-backup/tools/cliq-notify/relay.mjs --test-send    # one test message to Cliq
   node ~/multica-instruction-backup/tools/cliq-notify/relay.mjs --replay 3     # shows your last 3 real mentions as messages; sends nothing
   ```

5. **Run it:** `bash setup.sh --launchd` writes the launchd file; then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.balaji.multica-cliq.plist`. It starts at login and restarts if it stops. Stop it with `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.balaji.multica-cliq.plist`. Logs: `~/.local/state/multica-cliq/relay.log`.
   **After editing relay.mjs or config, restart the service**: `launchctl kickstart -k gui/$(id -u)/com.balaji.multica-cliq` (launchd does not restart on file changes). Run only one relay at a time.

## Behaviour you should know
- **First start** marks your existing mentions as already seen and sends nothing (otherwise you would get about 80 old messages). Use `--backfill 3` once if you want the last 3.
- **Sleep or network loss:** after the Mac wakes, it reconnects and sends the mentions you missed (up to 24 hours back, once each). State is in `~/.local/state/multica-cliq/state.json`.
- **VPN:** not needed. It talks to `api.multica.ai` and to Cliq only.
- **Limits:** one message per 1.1 seconds, four tries per message; a rejected key is not retried and is logged without the key.
- **Settings** (`config.json`): `types` (default `["mentioned"]`; add `"new_comment"` or `"status_changed"` to get those too), `snippet_chars` (0 = headline and link only), `poll_minutes`, `catchup_max_age_hours`.
- **Your Multica login** is read from the Multica CLI profile at run time and is never copied. For a dedicated token put `MULTICA_TOKEN=` in `secrets.env`.
- **Not in the backup repo:** the secrets file lives in `~/.config/multica-cliq/`. The GitHub repo of the backup folder is public; never copy the secrets file or the endpoint URL into it.

## Tests (no Cliq, no network writes)
```
node tools/cliq-notify/test.mjs        # 20 checks: filtering, dedupe, retry, masking, restart, burst, token refresh
node tools/cliq-notify/test-live.mjs   # 7 checks: websocket login, push, drop and reconnect
```

## Next step (not built): replying from Cliq
A bot message handler in Cliq calls Multica's comment API with a token you create. See the feasibility notes in the Multica CirDoc skill.

## If you use the OAuth route (CLIQ_BOT + client id/secret): get the refresh token with the tool, do not paste the code
In the Zoho API console (your region, e.g. https://api-console.zoho.in) > Self Client > Generate Code, scope `ZohoCliq.Webhooks.CREATE`, then run
`node tools/cliq-notify/relay.mjs --exchange-code` and paste the code when asked. The tool exchanges it and saves `CLIQ_REFRESH_TOKEN` itself (mode 600, never printed).
The code from "Generate Code" is NOT the refresh token: it lives about 3 minutes and works once, and putting it in `CLIQ_REFRESH_TOKEN` gives `invalid_code`.
Error `oauth_app_blocked` comes from Zoho (cause unknown from here); see the message printed by `--check`.
