#include "omoide.h"

#include <ftw.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static int remove_entry(const char *path, const struct stat *st, int flag, struct FTW *ftw) {
  (void)st;
  (void)flag;
  (void)ftw;
  remove(path);
  return 0;   // keep going: this is best-effort, like rmtree(ignore_errors=True)
}

// A directory and everything under it, without following a symlink anywhere:
// a symlinked root is refused outright and a symlinked entry is unlinked, not
// descended through. It is the one safe way to delete a tree someone else may
// have planted links in.
void remove_tree(const char *path) {
  struct stat st;
  if (lstat(path, &st) != 0 || !S_ISDIR(st.st_mode))
    return;
  nftw(path, remove_entry, 16, FTW_DEPTH | FTW_PHYS);
}

// A memory's blob directory. Its id comes from the database, but it is still
// only ever one path component under blobs/. An id that is not would be a
// way to delete something else.
char *blob_dir_of(const char *memory_id) {
  if (!memory_id || !*memory_id || strchr(memory_id, '/') || g_str_equal(memory_id, ".")
      || g_str_equal(memory_id, ".."))
    return NULL;
  return g_build_filename(paths()->blob_dir, memory_id, NULL);
}

// Esc on a draft leaves nothing behind: row, blocks and blob all go.
//
// drafts_only is the safety catch. A compose overlay can outlive the commit it
// triggered, and dismissing it must never destroy a finished memory. Deleting
// a saved memory is `delete`, which asks for it explicitly.
bool discard(sqlite3 *db, const char *memory_id, bool drafts_only) {
  g_autoptr(sqlite3_stmt) row = db_query(db, "SELECT status FROM memories WHERE id = ?", "s", memory_id);
  if (!db_step(row))
    return false;
  if (drafts_only && g_strcmp0(col_str(row, "status"), "draft") != 0)
    return false;

  db_exec(db, "BEGIN");
  g_autoptr(sqlite3_stmt) del = db_query(db, "DELETE FROM memories WHERE id = ?", "s", memory_id);
  db_step(del);
  g_autoptr(sqlite3_stmt) fts = db_query(db, "DELETE FROM memories_fts WHERE memory_id = ?", "s", memory_id);
  db_step(fts);
  db_exec(db, "COMMIT");

  g_autofree char *dir = blob_dir_of(memory_id);
  if (dir)
    remove_tree(dir);
  return true;
}
