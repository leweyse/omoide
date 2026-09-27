#include "omoide.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>

// An XDG base directory, or its default under $HOME.
//
// A relative value is ignored, as the spec says to: it would otherwise resolve
// against whatever directory the CLI happened to be started in.
static char *xdg(const char *var, const char *fallback) {
  const char *value = g_getenv(var);
  if (value && value[0] == '/')
    return g_strdup(value);
  return g_build_filename(g_get_home_dir(), fallback, NULL);
}

// Plain XDG, deliberately NOT under an "omarchy" subdirectory:
// ~/.local/share/omarchy is a symlink to the read-only package tree
// (/usr/share/omarchy) on a stock install.
//
// Every path ends in a component written literally here, and there is no
// variable to move it. That is the whole of uninstall's safety: it deletes
// these paths, so what it deletes is always a directory named "omoide" that we
// created. Relocate them by pointing XDG_*_HOME elsewhere.
const Paths *paths(void) {
  static Paths p;
  if (!p.data_dir) {
    g_autofree char *data = xdg("XDG_DATA_HOME", ".local/share");
    g_autofree char *state = xdg("XDG_STATE_HOME", ".local/state");
    g_autofree char *config = xdg("XDG_CONFIG_HOME", ".config");
    p.data_dir = g_build_filename(data, "omoide", NULL);
    p.state_dir = g_build_filename(state, "omoide", NULL);
    p.db_path = g_build_filename(p.data_dir, "memories.db", NULL);
    p.blob_dir = g_build_filename(p.data_dir, "blobs", NULL);
    p.index_path = g_build_filename(p.state_dir, "index.json", NULL);
    p.config_path = g_build_filename(config, "omoide", "config.json", NULL);
    p.log_path = g_build_filename(p.state_dir, "omoide.log", NULL);
  }
  return &p;
}

// Where `path` really points, resolving symlinks in whatever part of it
// exists yet, because the data directory is usually created after this check.
static char *resolve(const char *path) {
  g_autofree char *head = g_strdup(path);
  GString *tail = g_string_new(NULL);
  char resolved[PATH_MAX];
  for (;;) {
    if (realpath(head, resolved))
      break;
    if (errno != ENOENT || g_strcmp0(head, "/") == 0) {
      g_string_free(tail, TRUE);
      return g_strdup(path);
    }
    g_autofree char *base = g_path_get_basename(head);
    g_autofree char *parent = g_path_get_dirname(head);
    g_string_prepend(tail, base);
    g_string_prepend_c(tail, '/');
    g_free(head);
    head = g_steal_pointer(&parent);
  }
  char *result = g_strconcat(resolved, tail->str, NULL);
  g_string_free(tail, TRUE);
  return result;
}

// Refuse to write into the Omarchy package tree.
void guard_paths(void) {
  const Paths *p = paths();
  g_autofree char *config_dir = g_path_get_dirname(p->config_path);
  const struct {
    const char *label;
    const char *path;
  } dirs[] = {
    { "data", p->data_dir },
    { "state", p->state_dir },
    { "config", config_dir },
  };
  for (size_t i = 0; i < G_N_ELEMENTS(dirs); i++) {
    g_autofree char *real = resolve(dirs[i].path);
    if (g_str_has_prefix(real, "/usr/"))
      die(1,
          "refusing to use %s as the %s directory: that is inside the "
          "read-only Omarchy package tree",
          real, dirs[i].label);
  }
}
