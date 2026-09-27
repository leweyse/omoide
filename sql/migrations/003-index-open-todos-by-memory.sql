-- Every memory card counts its open to-dos. Without this index SQLite answers
-- that count through idx_items_kind, which walks every open to-do in the
-- library once per card, so the count grows with the library instead of with
-- the memory.
CREATE INDEX idx_items_memory_open ON items (memory_id, kind, status, completed_at);
