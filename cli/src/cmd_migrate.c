#include "omoide.h"

int cmd_migrate(int argc, char **argv) {
  parse_options("migrate", NULL, 0, &argc, &argv);
  sqlite3 *db = db_open(true);
  json_object *out = json_object_new_object();
  json_object_object_add(out, "schemaVersion", json_object_new_int(db_user_version(db)));
  emit(out);
  return 0;
}
