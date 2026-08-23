-- Omoide, schema v1.
--
-- A memory is a document of ordered, typed blocks rather than a fixed record,
-- because what a capture yields varies: an article gives a source, a summary
-- and key points; an event listing gives a date and something to attend; a
-- screenshot of a design board gives an image and a list of names.
--
-- Two rules keep that open-ended without becoming a mess. `type` and `position`
-- stay queryable in SQL, so ordering and filtering are the database's job; and
-- the payload is JSON, so a new block type is a renderer plus a validator entry
-- and no migration at all.

CREATE TABLE memories (
  id          TEXT PRIMARY KEY,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL,
  kind        TEXT NOT NULL DEFAULT 'capture',
  title       TEXT,
  lede        TEXT,
  ocr_text    TEXT,
  status      TEXT NOT NULL DEFAULT 'draft',   -- draft | ready | archived
  ai_status   TEXT NOT NULL DEFAULT 'none',    -- none | pending | ok | failed
  -- Why an enrichment failed. NULL when none has. Cleared on success, so a
  -- stale reason cannot outlive the problem it described.
  ai_error    TEXT
);

CREATE TABLE blocks (
  id         TEXT PRIMARY KEY,
  memory_id  TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  position   INTEGER NOT NULL,
  type       TEXT NOT NULL,
  payload    TEXT NOT NULL DEFAULT '{}',
  -- Keeps a re-run of the agent from overwriting anything the user wrote.
  origin     TEXT NOT NULL DEFAULT 'ai',       -- ai | user | capture
  edited     INTEGER NOT NULL DEFAULT 0,
  UNIQUE (memory_id, position)
);

CREATE TABLE attachments (
  id         TEXT PRIMARY KEY,
  memory_id  TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  kind       TEXT NOT NULL,                    -- image | audio
  rel_path   TEXT NOT NULL,                    -- relative to the data dir
  thumb_path TEXT,
  mime       TEXT,
  bytes      INTEGER,
  -- Pixel dimensions, so a capture can be laid out at its own aspect before
  -- the image loads. Without them every surface has to guess a ratio and then
  -- crop the selection to fit it. NULL means not measured.
  width      INTEGER,
  height     INTEGER
);

-- The things a capture produced. `kind` is what makes a new kind of thing
-- cheap: a note, a contact or a place later is a value, a delegate and a nav
-- entry, with no DDL.
CREATE TABLE items (
  id                TEXT PRIMARY KEY,
  memory_id         TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  block_id          TEXT,
  kind              TEXT NOT NULL,             -- todo | event
  title             TEXT NOT NULL,
  notes             TEXT,
  due_at            TEXT,                      -- todo only; NULL = undated
  starts_at         TEXT,                      -- event only
  ends_at           TEXT,
  all_day           INTEGER NOT NULL DEFAULT 0,
  location          TEXT,
  map_url           TEXT,
  rrule             TEXT,
  status            TEXT NOT NULL DEFAULT 'active',  -- active | cancelled
  completed_at      TEXT,                      -- todo only: the check box
  source            TEXT NOT NULL DEFAULT 'ai',      -- ai | manual
  created_at        TEXT NOT NULL,
  -- Calendar sync holds the remote identity here, so it stays a mapping job
  -- rather than a schema change.
  external_provider TEXT,
  external_id       TEXT,
  external_etag     TEXT
);

-- Alarms, separate from the things they belong to.
--
-- A to-do can have a reminder, and a reminder can belong to something that is
-- not a to-do: an event wants "30 minutes before" just as much, and one item
-- can carry several at once. Putting the alarm on the item as a column makes
-- both of those a painful migration later. This is the iCalendar shape, VTODO
-- and VEVENT with VALARM children.
--
-- fire_at is always absolute so the scheduler reads one column, but
-- trigger_offset_min is kept: moving an event has to move its alarms with it,
-- and a calendar export needs the original relative TRIGGER.
CREATE TABLE reminders (
  id                 TEXT PRIMARY KEY,
  item_id            TEXT NOT NULL REFERENCES items (id) ON DELETE CASCADE,
  fire_at            TEXT NOT NULL,
  trigger_offset_min INTEGER,                  -- NULL = absolute; -30 = before
  status             TEXT NOT NULL DEFAULT 'pending',  -- pending|fired|cancelled
  unit               TEXT                      -- systemd unit name
);

CREATE TABLE tags (
  memory_id TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  tag       TEXT NOT NULL,
  PRIMARY KEY (memory_id, tag)
);

CREATE TABLE collections (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);

CREATE TABLE memory_collections (
  memory_id     TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  collection_id TEXT NOT NULL REFERENCES collections (id) ON DELETE CASCADE,
  position      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (memory_id, collection_id)
);

-- Related captures, and only what the user decided.
--
-- Nothing is inferred: relatedness between two captures is a judgement about
-- meaning, and a score over shared tags and word overlap either offers
-- everything or nothing with no useful middle.
--
-- One row per pair, ordered so (a,b) and (b,a) cannot both exist, and queried
-- with `from_id = ? OR to_id = ?` so the link is symmetric without a second
-- row to keep in sync.
CREATE TABLE links (
  from_id    TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  to_id      TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (from_id, to_id)
);

-- Search over titles, ledes, block text and OCR output. Rebuilt by the CLI
-- rather than by triggers: a block's searchable text lives inside a JSON
-- payload, which SQL cannot read out on its own.
CREATE VIRTUAL TABLE memories_fts USING fts5 (
  memory_id UNINDEXED,
  title,
  lede,
  body,
  ocr_text,
  tokenize = "unicode61 remove_diacritics 2"
);

CREATE INDEX idx_memories_created ON memories (created_at DESC);
CREATE INDEX idx_memories_status  ON memories (status, ai_status);
CREATE INDEX idx_blocks_memory    ON blocks (memory_id, position);
CREATE INDEX idx_attachments_memory ON attachments (memory_id);
CREATE INDEX idx_items_memory     ON items (memory_id);
CREATE INDEX idx_items_due        ON items (due_at);
CREATE INDEX idx_items_kind       ON items (kind, status, completed_at);
CREATE INDEX idx_reminders_item   ON reminders (item_id);
CREATE INDEX idx_reminders_status ON reminders (status, fire_at);
CREATE INDEX idx_links_to         ON links (to_id);
