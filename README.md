# n8n + Postgres stack for the real-estate listing collector

Two containers, both persisted with named Docker volumes so data survives restarts:

- **n8n** — runs your workflows (Gmail trigger, parsing, notifications). Uses its own internal SQLite database (default), stored in the `n8n_data` volume — you don't need to manage that yourself.
- **postgres** — a separate database, purely for the `listings` data your workflows will write to. Kept independent from n8n's internal state on purpose: easier to back up, query with any DB tool, or rebuild n8n without touching your collected data.

## Quick start

1. Copy the env template and set your own password:

   ```bash
   cp .env.example .env
   ```

   Edit `.env` and change `POSTGRES_PASSWORD` to something real.

2. Start the stack:

   ```bash
   docker compose up -d
   ```

3. Open n8n at http://localhost:5678 and create your owner account (first run only).

4. In n8n, add a **Postgres credential** (Settings → Credentials → New):
   - Host: `postgres`  (the Docker service name — NOT `localhost`, since n8n reaches Postgres over the internal Docker network)
   - Port: `5432`
   - Database: value of `POSTGRES_DB` from your `.env`
   - User / Password: from your `.env`
   - SSL: disable (not needed inside the Docker network)

5. Verify the schema was created:

   ```bash
   docker exec -it immo_postgres psql -U immo_user -d immobilien -c "\dt"
   ```

   You should see `listings` and `price_history`.

## Notes

- `N8N_SECURE_COOKIE=false` is set because this is a local-only stack accessed over plain `http://localhost`. If you ever expose n8n to the internet (e.g. to receive real webhooks), put it behind HTTPS via a reverse proxy such as Caddy or Traefik and remove that variable instead of leaving it disabled.
- The `./init/001_schema.sql` file only runs automatically the very first time the Postgres volume is created. If you edit the schema later, apply changes manually, e.g.:

  ```bash
  docker exec -it immo_postgres psql -U immo_user -d immobilien -f /docker-entrypoint-initdb.d/001_schema.sql
  ```

  or just connect with `psql`/a GUI client and run `ALTER TABLE` statements yourself.

- Backup the listings data any time with:

  ```bash
  docker exec immo_postgres pg_dump -U immo_user immobilien > backup.sql
  ```

- To stop the stack without losing data: `docker compose down` (volumes persist). To wipe everything and start fresh: `docker compose down -v`.

## Syncing workflows from local JSON files

There's a `./workflows` folder in this stack, mounted into the n8n container at `/workflows`. Drop any workflow `.json` file (exported from n8n, or one I hand you) into that local folder, then run:

```bash
docker exec -it n8n n8n import:workflow --separate --input=/workflows
```

- `--separate` tells it to read every `*.json` file in the given directory (not just one file).
- If a workflow's `id` in the JSON matches one already in your instance, it gets **overwritten** with the file's contents — that's what makes this a repeatable "sync", not just a one-time import.
- If the `id` doesn't exist yet, it's created as a new workflow.
- New/changed workflows won't show as active until you (re-)activate them in the UI, or you also pass a flag like `--activeState=fromJson` if you want the file's active/inactive state applied automatically.

To go the other direction (pull what's currently in n8n back out to files, e.g. before editing or for backup):

```bash
docker exec -it n8n n8n export:workflow --backup --output=/workflows
```

Two other ways to get a workflow into n8n, for one-off cases:

- **UI import**: open a workflow (or a blank canvas) → the `⋯` menu top right → *Import from File* → pick the JSON. Good for a single workflow, no CLI needed.
- **Git-based Source Control**: n8n has a built-in push/pull Git integration (Settings → Source Control) for a more "real" sync against a repo. Whether it's available on your self-hosted instance depends on your n8n license/plan — check that menu in your own instance to see if it's offered; if not, the CLI approach above is the free equivalent for a personal setup.

## Test workflow: `00_test_postgres_connection.json`

Already sitting in `./workflows`. It's the smallest possible thing that proves the whole chain works, before we build the real Gmail parsing logic: a **Manual Trigger** node followed by a **Postgres** node that upserts one fake listing (`portal='test'`, `expose_id='test-1'`) into your `listings` table.

Try it:

1. Make sure the stack is running (`docker compose up -d`) and you've already created a Postgres credential in n8n (see Quick start step 4).
2. Import it:

   ```bash
   docker exec -it n8n n8n import:workflow --separate --input=/workflows
   ```

3. Open n8n in the browser → you'll see a workflow called **"00 - Test Postgres Connection"**.
4. Open it and click the **Postgres node** ("Upsert test listing"). The credential field will show as unlinked (credential IDs aren't portable between instances) — pick your own Postgres credential from the dropdown and save.
5. Click **"Execute workflow"** (bottom of canvas, or the button on the Manual Trigger node).
6. You should see a green checkmark and, in the output panel of the Postgres node, one returned row — the listing you just inserted.
7. Run it a second time. Same result, but now it went through the `ON CONFLICT ... DO UPDATE` branch instead of inserting a duplicate — that's your dedupe logic already proven to work.
8. Double-check from the DB side directly:

   ```bash
   docker exec -it immo_postgres psql -U immo_user -d immobilien -c "SELECT * FROM listings;"
   ```

   You should see exactly one row, no matter how many times you executed the workflow.

If this works end to end, the stack (Docker → n8n → Postgres → schema) is fully proven, and the only remaining piece for the real thing is swapping the Manual Trigger + hardcoded values for a Gmail Trigger + parsed email data.

## Next step

Once the test workflow above works, the next piece is the actual n8n workflow: Gmail Trigger → parse the listing emails → dedupe-check against `listings.expose_id` → INSERT/UPDATE → Telegram notification. That can be built as an importable workflow JSON on top of this stack — and it'll use exactly the sync process above to load it in and push future edits back and forth.
