// Command-line parsing shared by every command.
#include "omoide.h"

#include <string.h>

void parse_options(
    const char *command, const GOptionEntry *entries, int max_positional, int *argc, char ***argv) {
  g_autoptr(GOptionContext) context = g_option_context_new(NULL);
  g_autofree char *summary = g_strdup_printf("omoide %s", command);
  g_option_context_set_summary(context, summary);

  // String options are read as FILENAME, which GLib passes through as bytes.
  // As STRING it converts them from the process locale, which is "C" here --
  // deliberately, so dates print in English -- and so refused any note or
  // title with an accent in it. The bytes are made valid UTF-8 below, whatever
  // the locale, which is what argparse accepted too.
  size_t count = 0;
  while (entries && entries[count].long_name)
    count++;
  g_autofree GOptionEntry *mutable = g_new0(GOptionEntry, count + 1);
  for (size_t i = 0; i < count; i++) {
    mutable[i] = entries[i];
    if (mutable[i].arg == G_OPTION_ARG_STRING)
      mutable[i].arg = G_OPTION_ARG_FILENAME;
  }
  g_option_context_add_main_entries(context, mutable, NULL);

  static GStrv args = NULL;   // for the rest of the process: argv points into it
  g_strfreev(args);
  args = g_new0(char *, *argc + 1);
  for (int i = 0; i < *argc; i++)
    args[i] = g_strdup((*argv)[i]);
  g_autoptr(GError) error = NULL;
  if (!g_option_context_parse_strv(context, &args, &error))
    die(2, "%s: %s", command, error->message);
  for (size_t i = 0; i < count; i++) {
    char **value = entries[i].arg == G_OPTION_ARG_STRING ? entries[i].arg_data : NULL;
    if (value && *value && !g_utf8_validate(*value, -1, NULL)) {
      char *valid = g_utf8_make_valid(*value, -1);
      g_free(*value);
      *value = valid;
    }
  }
  for (size_t i = 0; args[i]; i++) {
    if (!g_utf8_validate(args[i], -1, NULL)) {
      char *valid = g_utf8_make_valid(args[i], -1);
      g_free(args[i]);
      args[i] = valid;
    }
  }
  *argv = args;
  *argc = (int)g_strv_length(args);
  if (*argc - 1 > max_positional) {
    g_autofree char *extra = g_strjoinv(" ", *argv + 1 + max_positional);
    die(2, "%s: unrecognized arguments: %s", command, extra);
  }
}

void require_option(const char *command, const char *flag, const char *value) {
  if (!value)
    die(2, "%s: the following arguments are required: %s", command, flag);
}

void require_choice(const char *command, const char *what, const char *value, const char *const *choices) {
  for (size_t i = 0; choices[i]; i++)
    if (g_strcmp0(value, choices[i]) == 0)
      return;
  g_autofree char *listed = g_strjoinv("', '", (char **)choices);
  die(2, "%s: argument %s: invalid choice: '%s' (choose from '%s')", command, what, value ? value : "",
      listed);
}

// The first positional, or NULL. After parse_options, argv[0] is the command.
const char *positional(int argc, char **argv) {
  return argc > 1 ? argv[1] : NULL;
}
