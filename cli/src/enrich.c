// The agent: how it is invoked, what its answer may contain, and how that
// answer lands on a memory.
#include "omoide.h"

#include <glib/gstdio.h>
#include <math.h>
#include <string.h>

// Ceilings on what one agent answer may turn into. They are not a guess at a
// good answer, which the prompt already asks to be a handful of blocks. They
// are the point past which a reply stops being an answer and starts filling a
// database or the session's timer table. A capture is OCR of someone else's
// page, so the number is not ours to trust.
enum {
  MAX_BLOCKS = 24,   // a real capture yields four or five
  MAX_LIST_ITEMS = 20,
  MAX_TODOS = 20,
  MAX_EVENTS = 8,
  MAX_TAGS = 8,
  MAX_LEDE = 400,
  MAX_BODY = 4000,   // summary, text, quote, code
  MAX_TAG = 40,
  MAX_TEXT = 2000,   // default ceiling for every clean_text field
  AGENT_OUTPUT_CAP = 1024 * 1024,   // a JSON answer that needs a megabyte is not one
};

// Renderer-owned labels. If a model sends one as a list heading it is dropped,
// so headings cannot drift in wording or language between captures.
static const char *const CANONICAL_LABELS[] = { "summary", "event date", "to-dos", "todos", "to dos", NULL };

static const char prompt_template[] = {
#embed "../../prompts/enrich.txt"
  , 0
};

char *clean_text(json_object *value, long limit) {
  if (!truthy(value))
    return g_strdup("");
  g_autofree char *text = as_text(value);
  g_autofree char *flat = re_replace("\\s+", text, " ");
  g_autofree char *stripped = strip_space(flat);
  return truncate_chars(stripped, limit);
}

// A model-supplied URL is only ever handed to a browser, so http(s) is the
// whole allowed set. Anything else, such as file://, javascript: or a bare
// word, is dropped. map_url ends up behind a button that says "Google Maps", so the
// label and the destination must not be free to disagree.
#define HTTP_URL "^(https?)://([^/\\s]+)"

char *http_url(json_object *value) {
  g_autofree char *url = clean_text(value, MAX_TEXT);
  if (g_regex_match(re(HTTP_URL, G_REGEX_CASELESS), url, 0, NULL))
    return g_steal_pointer(&url);
  return g_strdup("");
}

// At most MAX_REMINDERS well-formed alarms. Each becomes a row that will
// interrupt someone, so this list's length is one a model wrote about someone
// else's web page.
static json_object *clean_reminders(json_object *raw) {
  json_object *out = json_object_new_array();
  for (size_t i = 0;
      json_object_is_type(raw, json_type_array) && i < json_object_array_length(raw) && i < MAX_REMINDERS;
      i++) {
    json_object *entry = json_object_array_get_idx(raw, i);
    if (json_object_is_type(entry, json_type_object)
        && (json_object_object_get_ex(entry, "at", NULL)
            || json_object_object_get_ex(entry, "offset_min", NULL)))
      json_object_array_add(out, json_object_get(entry));
  }
  return out;
}

static bool in_list(const char *value, const char *const *list) {
  for (size_t i = 0; list[i]; i++)
    if (g_strcmp0(value, list[i]) == 0)
      return true;
  return false;
}

// `a or b`: the first when it is truthy, else the second.
static json_object *either(json_object *raw, const char *a, const char *b) {
  json_object *first = json_get(raw, a);
  return truthy(first) ? first : json_get(raw, b);
}

static GDateTime *parse_value(json_object *value) {
  if (!truthy(value))
    return NULL;
  g_autofree char *text = as_text(value);
  return parse_iso(text);
}

static json_object *text_field(json_object *raw, const char *key) {
  g_autofree char *text = clean_text(json_get(raw, key), MAX_TEXT);
  return json_object_new_string(text);
}

// Drop anything malformed rather than storing it. The main quality risk with a
// generous prompt is an over-eager model that emits an empty list on every
// capture, so emptiness is a validation failure, not a blank card.
static json_object *validate_blocks(json_object *raw_blocks) {
  json_object *result = json_object_new_array();
  if (!json_object_is_type(raw_blocks, json_type_array))
    return result;

  int events = 0;
  const size_t offered = json_object_array_length(raw_blocks);
  for (size_t b = 0; b < offered; b++) {
    if (json_object_array_length(result) >= MAX_BLOCKS) {
      g_autofree char *kept = g_strdup_printf("%d", MAX_BLOCKS);
      g_autofree char *count = g_strdup_printf("%zu", offered);
      log_event("ai.truncated", "what", "blocks", "kept", kept, "offered", count, NULL);
      break;
    }
    json_object *raw = json_object_array_get_idx(raw_blocks, b);
    if (!json_object_is_type(raw, json_type_object))
      continue;
    json_object *type = json_get(raw, "type");
    g_autofree char *type_text = truthy(type) ? as_text(type) : g_strdup("");
    g_autofree char *type_stripped = strip_space(type_text);
    g_autofree char *kind = g_utf8_strdown(type_stripped, -1);
    json_object *block = json_object_new_object();

    if (g_str_equal(kind, "source")) {
      g_autofree char *url = clean_text(json_get(raw, "url"), MAX_TEXT);
      g_autoptr(GMatchInfo) match = NULL;
      if (!g_regex_match(re(HTTP_URL, G_REGEX_CASELESS), url, 0, &match)) {
        json_object_put(block);
        continue;
      }
      g_autofree char *host = g_match_info_fetch(match, 2);
      g_autofree char *domain = g_utf8_strdown(host, -1);
      json_object *payload = json_object_new_object();
      json_object_object_add(payload, "url", json_object_new_string(url));
      json_object_object_add(payload, "domain", json_object_new_string(domain));
      json_object_object_add(payload, "title", text_field(raw, "title"));
      json_object_object_add(payload, "byline", text_field(raw, "byline"));
      json_object_object_add(payload, "chip", text_field(raw, "chip"));
      json_object_object_add(block, "payload", payload);

    } else if (g_str_equal(kind, "summary") || g_str_equal(kind, "text") || g_str_equal(kind, "quote")
        || g_str_equal(kind, "code")) {
      // Not clean_text: a summary keeps its newlines. Still capped.
      json_object *text = json_get(raw, "text");
      g_autofree char *raw_text = truthy(text) ? as_text(text) : g_strdup("");
      g_autofree char *stripped = strip_space(raw_text);
      g_autofree char *body = truncate_chars(stripped, MAX_BODY);
      if (!*body) {
        json_object_put(block);
        continue;
      }
      json_object *payload = json_object_new_object();
      json_object_object_add(payload, "text", json_object_new_string(body));
      if (g_str_equal(kind, "quote"))
        json_object_object_add(payload, "attribution", text_field(raw, "attribution"));
      if (g_str_equal(kind, "code"))
        json_object_object_add(payload, "language", text_field(raw, "language"));
      json_object_object_add(block, "payload", payload);

    } else if (g_str_equal(kind, "list")) {
      json_object *items = json_object_new_array();
      json_object *entries = json_get(raw, "items");
      for (size_t i = 0; json_object_is_type(entries, json_type_array)
          && i < json_object_array_length(entries) && i < MAX_LIST_ITEMS;
          i++) {
        json_object *entry = json_object_array_get_idx(entries, i);
        g_autofree char *text = NULL, *label = NULL;
        if (json_object_is_type(entry, json_type_string)) {
          text = clean_text(entry, MAX_TEXT);
          label = g_strdup("");
        } else if (json_object_is_type(entry, json_type_object)) {
          text = clean_text(json_get(entry, "text"), MAX_TEXT);
          label = clean_text(json_get(entry, "label"), MAX_TEXT);
        }
        if (!text || !*text)
          continue;
        json_object *item = json_object_new_object();
        json_object_object_add(item, "label", json_object_new_string(label));
        json_object_object_add(item, "text", json_object_new_string(text));
        json_object_array_add(items, item);
      }
      if (json_object_array_length(items) == 0) {
        json_object_put(items);
        json_object_put(block);
        continue;
      }
      g_autofree char *heading = clean_text(json_get(raw, "heading"), MAX_TEXT);
      g_autofree char *canonical = g_utf8_strdown(heading, -1);
      for (size_t n = strlen(canonical); n > 0 && canonical[n - 1] == ':'; n--)
        canonical[n - 1] = '\0';
      json_object *payload = json_object_new_object();
      json_object_object_add(
          payload, "heading", json_object_new_string(in_list(canonical, CANONICAL_LABELS) ? "" : heading));
      json_object_object_add(payload, "ordered", json_object_new_boolean(truthy(json_get(raw, "ordered"))));
      json_object_object_add(payload, "items", items);
      json_object_object_add(block, "payload", payload);

    } else if (g_str_equal(kind, "event")) {
      // Every event is created active and gets an alarm, so this is the one
      // block type where the count alone decides how many timers a single
      // capture can put on the machine.
      g_autoptr(GDateTime) starts =
          events < MAX_EVENTS ? parse_value(either(raw, "start", "starts_at")) : NULL;
      if (!starts) {
        json_object_put(block);
        continue;
      }
      events++;
      g_autoptr(GDateTime) ends = parse_value(either(raw, "end", "ends_at"));
      g_autofree char *title = clean_text(json_get(raw, "title"), MAX_TEXT);
      g_autofree char *starts_at = iso(starts);
      g_autofree char *ends_at = ends ? iso(ends) : NULL;
      g_autofree char *map_url = http_url(json_get(raw, "map_url"));
      json_object *suggested = json_get(raw, "suggested");
      json_object *item = json_object_new_object();
      json_object_object_add(item, "kind", json_object_new_string("event"));
      json_object_object_add(item, "title", json_object_new_string(*title ? title : "Event"));
      json_object_object_add(item, "starts_at", json_object_new_string(starts_at));
      json_object_object_add(item, "ends_at", json_str(ends_at));
      json_object_object_add(item, "all_day", json_object_new_int(truthy(json_get(raw, "all_day")) ? 1 : 0));
      json_object_object_add(item, "location", text_field(raw, "location"));
      json_object_object_add(item, "map_url", json_object_new_string(map_url));
      json_object_object_add(item, "remind", clean_reminders(json_get(raw, "remind")));
      json_object_object_add(item, "suggested",
          json_object_object_get_ex(raw, "suggested", NULL) ? json_object_get(suggested)
                                                            : json_object_new_boolean(true));
      json_object_object_add(block, "item", item);

    } else if (g_str_equal(kind, "todos")) {
      json_object *items = json_object_new_array();
      json_object *entries = json_get(raw, "items");
      for (size_t i = 0; json_object_is_type(entries, json_type_array)
          && i < json_object_array_length(entries) && i < MAX_TODOS;
          i++) {
        json_object *entry = json_object_array_get_idx(entries, i);
        if (!json_object_is_type(entry, json_type_object))
          continue;
        g_autofree char *title = clean_text(json_get(entry, "title"), MAX_TEXT);
        if (!*title)
          continue;
        g_autoptr(GDateTime) due = parse_value(json_get(entry, "due_at"));
        g_autofree char *due_at = due ? iso(due) : NULL;
        json_object *todo = json_object_new_object();
        json_object_object_add(todo, "kind", json_object_new_string("todo"));
        json_object_object_add(todo, "title", json_object_new_string(title));
        json_object_object_add(todo, "due_at", json_str(due_at));
        json_object_object_add(todo, "remind", clean_reminders(json_get(entry, "remind")));
        // Suggested when the flag is missing, so an under-specified response
        // errs toward scheduling nothing.
        json_object_object_add(todo, "suggested",
            json_object_object_get_ex(entry, "suggested", NULL)
                ? json_object_get(json_get(entry, "suggested"))
                : json_object_new_boolean(true));
        json_object_array_add(items, todo);
      }
      if (json_object_array_length(items) == 0) {
        json_object_put(items);
        json_object_put(block);
        continue;
      }
      json_object_object_add(block, "items", items);

    } else {
      // Unknown, or note and image, which the capture inserts and the model
      // never does.
      json_object_put(block);
      continue;
    }
    json_object_object_add(block, "type", json_object_new_string(kind));
    json_object_array_add(result, block);
  }
  return result;
}

// --- reading an answer

// The whole text as one JSON value, or NULL.
static json_object *parse_whole(const char *text) {
  g_autoptr(json_tokener) tok = json_tokener_new();
  json_tokener_set_flags(tok, JSON_TOKENER_STRICT);
  const int length = (int)strlen(text);
  json_object *value = json_tokener_parse_ex(tok, text, length);
  if (!value)
    return NULL;
  for (int i = (int)json_tokener_get_parse_end(tok); i < length; i++) {
    if (!g_ascii_isspace(text[i])) {
      json_object_put(value);
      return NULL;
    }
  }
  return value;
}

// The first JSON object in a model's stdout. Models wrap JSON in prose and
// fences, and some CLIs wrap it again in their own envelope, so reading the
// whole text is only the first try; after that, json-c is started at each "{"
// in turn and the first that reads as an object wins.
static json_object *extract_json(const char *text) {
  if (!text || !*text)
    return NULL;
  json_object *parsed = parse_whole(text);
  if (json_object_is_type(parsed, json_type_object)) {
    // Some CLIs return {"result": "<the actual answer>"}.
    const char *const envelopes[] = { "result", "response", "output", "content", "text" };
    for (size_t i = 0; i < G_N_ELEMENTS(envelopes); i++) {
      const char *inner = json_get_str(parsed, envelopes[i]);
      g_autofree char *trimmed = inner ? strip_space(inner) : NULL;
      if (trimmed && *trimmed) {
        json_object *nested = extract_json(inner);
        if (nested) {
          json_object_put(parsed);
          return nested;
        }
      }
    }
    if (json_object_object_get_ex(parsed, "blocks", NULL) || json_object_object_get_ex(parsed, "title", NULL))
      return parsed;
  }
  json_object_put(parsed);

  // Strict mode refuses anything after the value, and here there always is
  // something: the rest of the prose. So a lenient pass finds where the
  // object ends, and the strict one then reads exactly that much, which keeps
  // the strictness about the object itself.
  for (const char *start = strchr(text, '{'); start; start = strchr(start + 1, '{')) {
    g_autoptr(json_tokener) scan = json_tokener_new();
    g_autoptr(json_object) lenient = json_tokener_parse_ex(scan, start, (int)strlen(start));
    if (!lenient)
      continue;
    g_autoptr(json_tokener) tok = json_tokener_new();
    json_tokener_set_flags(tok, JSON_TOKENER_STRICT);
    json_object *candidate = json_tokener_parse_ex(tok, start, (int)json_tokener_get_parse_end(scan));
    if (json_object_is_type(candidate, json_type_object))
      return candidate;
    json_object_put(candidate);
  }
  return NULL;
}

// --- invoking the agent

static void add_args(GStrvBuilder *argv, const char *const *more) {
  for (size_t i = 0; more[i]; i++)
    g_strv_builder_add(argv, more[i]);
}

// Add each CLI's own way of saying "answer, do not act".
//
// A capture is OCR of whatever was on screen, so its text is untrusted in the
// ordinary sense: a page can contain a paragraph addressed to whatever reads
// it next. These are general coding agents with a shell, so the prompt has to
// arrive with their tools already shut off rather than relying on the model
// to decline.
GStrv harden(
    const char *const *base, const char *provider, bool vision, const char *image_path, GHashTable *env) {
  g_autoptr(GStrvBuilder) argv = g_strv_builder_new();
  add_args(argv, base);
  g_autofree char *folder = image_path ? g_path_get_dirname(image_path) : NULL;
  const bool attach = vision && image_path;

  if (g_strcmp0(provider, "claude") == 0) {
    // --tools controls which tools EXIST, where --allowed-tools only
    // pre-approves ones that still do. "" is documented as none at all. Read
    // alone is not enough in an empty working directory, because claude
    // refuses to read outside its workspace, so the capture's own folder is
    // granted.
    g_strv_builder_add_many(argv, "--tools", vision ? "Read" : "", NULL);
    if (attach)
      g_strv_builder_add_many(argv, "--add-dir", folder, NULL);
  } else if (g_strcmp0(provider, "codex") == 0) {
    // read-only restricts what a command may WRITE, not what it may read, so
    // the shell tool is switched off outright; the sandbox stays as the
    // backstop. --ephemeral keeps a picture of the screen out of codex's
    // session files on disk.
    g_strv_builder_add_many(argv, "-s", "read-only", "--ephemeral", "-c", "features.shell_tool=false", NULL);
    if (attach)
      g_strv_builder_add_many(argv, "-i", image_path, NULL);
  } else if (g_strcmp0(provider, "gemini") == 0) {
    // plan is gemini's own read-only mode.
    g_strv_builder_add_many(argv, "--approval-mode", "plan", NULL);
    if (attach)
      g_strv_builder_add_many(argv, "--include-directories", folder, NULL);
    // gemini refuses to run in a directory it does not trust, and the empty
    // one we hand it is by definition one of those. Trusting it grants
    // nothing: it is empty and ours.
    if (env)
      g_hash_table_insert(env, g_strdup("GEMINI_CLI_TRUST_WORKSPACE"), g_strdup("true"));
  } else if (g_strcmp0(provider, "opencode") == 0) {
    // OPENCODE_CONFIG_CONTENT merges over the user's opencode.json rather than
    // replacing it, so their providers survive and only permissions change.
    if (env) {
      g_autoptr(json_object) deny = json_object_new_object();
      const char *tools[] = { "bash", "edit", "read", "glob", "grep", "list", "task", "webfetch" };
      for (size_t i = 0; i < G_N_ELEMENTS(tools); i++)
        json_object_object_add(deny, tools[i], json_object_new_string("deny"));
      g_autoptr(json_object) config = json_object_new_object();
      json_object_object_add(config, "permission", json_object_get(deny));
      g_hash_table_insert(env, g_strdup("OPENCODE_CONFIG_CONTENT"),
          g_strdup(json_object_to_json_string_ext(config, JSON_C_TO_STRING_SPACED)));
    }
    g_strv_builder_add(argv, "--pure");
    if (attach)
      g_strv_builder_add_many(argv, "--file", image_path, NULL);
  }
  return g_strv_builder_end(argv);
}

static char *build_prompt(const char *note, const char *ocr_text, const char *image_path, bool vision) {
  g_autoptr(GDateTime) now = now_utc();
  g_autoptr(GDateTime) local = g_date_time_to_local(now);
  g_autofree char *note_capped = truncate_chars(note ? note : "", 4000);
  // Capped like the note. A clipboard capture decides how long these are, and
  // the full text is on the memory either way.
  g_autofree char *ocr_capped = truncate_chars(vision ? "" : (ocr_text ? ocr_text : ""), 8000);
  g_autofree char *now_iso = iso(local);
  g_autofree char *now_local = g_date_time_format(local, "%A %d %B %Y, %H:%M");

  g_autoptr(json_object) context = json_object_new_object();
  json_object_object_add(context, "note", json_object_new_string(note_capped));
  json_object_object_add(context, "ocr_text", json_object_new_string(ocr_capped));
  json_object_object_add(
      context, "image_path", json_object_new_string(vision && image_path ? image_path : ""));
  json_object_object_add(context, "now_iso", json_object_new_string(now_iso));
  json_object_object_add(context, "now_local", json_object_new_string(now_local));
  json_object_object_add(
      context, "timezone", json_object_new_string(g_date_time_get_timezone_abbreviation(local)));
  return g_strconcat(prompt_template, "\n\nINPUT:\n",
      json_object_to_json_string_ext(
          context, JSON_C_TO_STRING_PRETTY | JSON_C_TO_STRING_SPACED | JSON_C_TO_STRING_NOSLASHESCAPE),
      NULL);
}

static size_t length_of(json_object *value) {
  if (!truthy(value))
    return 0;
  if (json_object_is_type(value, json_type_array))
    return json_object_array_length(value);
  if (json_object_is_type(value, json_type_object))
    return (size_t)json_object_object_length(value);
  if (json_object_is_type(value, json_type_string))
    return (size_t)g_utf8_strlen(json_object_get_string(value), -1);
  return 0;
}

static char *seconds_since(gint64 started) {
  const double elapsed = (double)(g_get_monotonic_time() - started) / G_TIME_SPAN_SECOND;
  return py_float(round(elapsed * 10) / 10);
}

static char *count_text(size_t n) {
  return g_strdup_printf("%zu", n);
}

// Enrich, or say why not. Nothing here may take a capture down with it, and
// the reason it failed survives to the memory's error column.
json_object *run_ai(
    const char *note, const char *ocr_text, const char *image_path, json_object *ai, char **reason) {
  g_auto(GStrv) resolved = resolve_provider(ai);
  if (!resolved) {
    log_event("ai.skip", "reason", "no provider resolved", NULL);
    *reason = g_strdup("no agent is configured");
    return NULL;
  }

  g_autofree char *provider =
      truthy(json_get(ai, "provider")) ? as_text(json_get(ai, "provider")) : g_strdup("");
  const bool custom = truthy(json_get(ai, "command"));
  g_autofree char *vision_mode = as_text(json_get(ai, "visionMode"));
  const bool vision = g_str_equal(vision_mode, "image") && image_path && *image_path
      && (provider_takes_image(provider) || custom);
  const bool hardened = !custom && !provider_is_plain_model(provider);

  g_autoptr(GHashTable) env = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
  g_auto(GStrv) argv = hardened ? harden((const char *const *)resolved, provider, vision, image_path, env)
                                : g_strdupv(resolved);

  // An empty directory of our own, not whatever the shell happened to be
  // started in. Every provider scopes part of what it can touch to its working
  // directory, and this is the only restriction that also covers a custom
  // command, where there are no flags of ours to add.
  g_autofree char *workdir = g_build_filename(paths()->state_dir, "agent-cwd", NULL);
  if (g_mkdir_with_parents(workdir, 0777) != 0)
    g_clear_pointer(&workdir, g_free);

  json_object *timeout_ms = json_get(ai, "timeoutMs");
  const double timeout =
      MAX(5.0, (truthy(timeout_ms) ? json_object_get_double(timeout_ms) : 45000.0) / 1000.0);
  const gint64 started = g_get_monotonic_time();
  g_autofree char *program = g_path_get_basename(argv[0]);
  g_autofree char *timeout_text = py_float(timeout);
  g_autofree char *note_len = count_text((size_t)g_utf8_strlen(note ? note : "", -1));
  g_autofree char *ocr_len = count_text((size_t)g_utf8_strlen(ocr_text ? ocr_text : "", -1));
  log_event("ai.start", "program", program, "vision", vision ? "True" : "False", "timeout", timeout_text,
      "hardened", hardened ? "True" : "False", "note_len", note_len, "ocr_len", ocr_len, NULL);

  g_autofree char *prompt = build_prompt(note, ocr_text, image_path, vision);
  g_auto(ProcResult) proc =
      proc_run_agent((const char *const *)argv, prompt, timeout, workdir, env, AGENT_OUTPUT_CAP);
  g_autofree char *seconds = seconds_since(started);

  if (!proc.started) {
    g_autofree char *detail = one_line(proc.err, 300);
    log_event("ai.exception", "kind", "spawn", "detail", detail, NULL);
    g_autofree char *short_detail = one_line(proc.err, 200);
    *reason = g_strdup_printf("%s could not be run: %s", argv[0], short_detail);
    return NULL;
  }
  if (proc.timed_out) {
    log_event("ai.timeout", "seconds", seconds, NULL);
    *reason = g_strdup_printf("%s did not answer within %.0fs", argv[0], timeout);
    return NULL;
  }
  g_autofree char *rc = g_strdup_printf("%d", proc.status);
  if (proc.capped) {
    log_event("ai.exit", "rc", rc, "seconds", seconds, "detail", "output cap", NULL);
    *reason = g_strdup_printf("%s printed more than %dKB and was stopped", argv[0], AGENT_OUTPUT_CAP / 1024);
    return NULL;
  }
  if (proc.status != 0) {
    g_autofree char *err_line = one_line(proc.err, 300);
    g_autofree char *out_line = one_line(proc.out, 300);
    const char *detail = *err_line ? err_line : *out_line ? out_line : "no output";
    g_autofree char *err_len = count_text((size_t)g_utf8_strlen(proc.err, -1));
    g_autofree char *out_len = count_text((size_t)g_utf8_strlen(proc.out, -1));
    log_event("ai.exit", "rc", rc, "seconds", seconds, "err_len", err_len, "out_len", out_len, NULL);
    *reason = g_strdup_printf("%s exited %d: %s", argv[0], proc.status, detail);
    return NULL;
  }

  json_object *data = extract_json(proc.out);
  if (!truthy(data)) {
    json_object_put(data);
    g_autofree char *out_len = count_text((size_t)g_utf8_strlen(proc.out, -1));
    log_event("ai.unparsed", "seconds", seconds, "out_len", out_len, NULL);
    *reason = g_strdup_printf("%s replied without a JSON object", argv[0]);
    return NULL;
  }
  g_autofree char *blocks = count_text(length_of(json_get(data, "blocks")));
  g_autofree char *tags = count_text(length_of(json_get(data, "tags")));
  log_event("ai.ok", "seconds", seconds, "blocks", blocks, "tags", tags, NULL);
  return data;
}

// Write an agent's answer onto a memory. Returns how many to-dos it created.
// Shared by commit and enrich so a retry produces exactly what a first pass
// would. Blocks land with origin 'ai', which is what lets a retry tell its own
// output apart from the capture's and the user's.
int64_t apply_enrichment(sqlite3 *db, const char *memory_id, json_object *enriched) {
  g_autofree char *title = clean_text(json_get(enriched, "title"), MAX_TITLE);
  g_autofree char *lede = clean_text(json_get(enriched, "lede"), MAX_LEDE);
  if (*title) {
    g_autoptr(sqlite3_stmt) q =
        db_query(db, "UPDATE memories SET title = ? WHERE id = ?", "ss", title, memory_id);
    db_step(q);
  }
  if (*lede) {
    g_autoptr(sqlite3_stmt) q =
        db_query(db, "UPDATE memories SET lede = ? WHERE id = ?", "ss", lede, memory_id);
    db_step(q);
  }
  json_object *tags = json_get(enriched, "tags");
  for (size_t i = 0;
      json_object_is_type(tags, json_type_array) && i < json_object_array_length(tags) && i < MAX_TAGS; i++) {
    g_autofree char *clean = clean_text(json_object_array_get_idx(tags, i), MAX_TAG);
    g_autofree char *tag = g_utf8_strdown(clean, -1);
    if (!*tag)
      continue;
    g_autoptr(sqlite3_stmt) q =
        db_query(db, "INSERT OR IGNORE INTO tags (memory_id, tag) VALUES (?,?)", "ss", memory_id, tag);
    db_step(q);
  }

  int64_t created = 0;
  g_autoptr(json_object) blocks = validate_blocks(json_get(enriched, "blocks"));
  for (size_t i = 0; i < json_object_array_length(blocks); i++) {
    json_object *block = json_object_array_get_idx(blocks, i);
    const char *type = json_get_str(block, "type");
    if (g_str_equal(type, "todos")) {
      g_autofree char *block_id =
          add_block(db, memory_id, "todos", json_tokener_parse("{\"item_ids\": []}"), "ai");
      json_object *ids = json_object_new_array();
      json_object *items = json_get(block, "items");
      for (size_t t = 0; t < json_object_array_length(items); t++) {
        char *item_id = create_item(db, memory_id, block_id, json_object_array_get_idx(items, t), "ai");
        json_object_array_add(ids, json_object_new_string(item_id));
        g_free(item_id);
        created++;
      }
      json_object *payload = json_object_new_object();
      json_object_object_add(payload, "item_ids", ids);
      set_block_payload(db, block_id, payload);
    } else if (g_str_equal(type, "event")) {
      g_autofree char *block_id =
          add_block(db, memory_id, "event", json_tokener_parse("{\"item_id\": \"\"}"), "ai");
      g_autofree char *item_id = create_item(db, memory_id, block_id, json_get(block, "item"), "ai");
      json_object *payload = json_object_new_object();
      json_object_object_add(payload, "item_id", json_object_new_string(item_id));
      set_block_payload(db, block_id, payload);
    } else {
      g_autofree char *block_id =
          add_block(db, memory_id, type, json_object_get(json_get(block, "payload")), "ai");
    }
  }

  // Cleared, so a reason from an earlier attempt cannot outlive it.
  g_autoptr(sqlite3_stmt) done =
      db_query(db, "UPDATE memories SET ai_status = 'ok', ai_error = NULL WHERE id = ?", "s", memory_id);
  db_step(done);
  return created;
}

// Turn "remind me to call Ana tomorrow at 3pm" into a to-do, or nothing. It
// fires only on an explicit "remind me". Inferring intent from arbitrary prose
// is the guesswork the model is for.
#define REMIND_PREFIX "(?i)^\\s*(?:please\\s+)?remind\\s+me\\s+(?:to\\s+|that\\s+|about\\s+)?"
#define TRAILING_WHEN \
  "(?i)\\b(later\\s+today|tonight|tomorrow|today|in\\s+\\d+\\s*[a-z]+|" \
  "on\\s+\\w+|at\\s+\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)?|next\\s+\\w+|" \
  "mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:r|rs|rsday)?|" \
  "fri(?:day)?|sat(?:urday)?|sun(?:day)?)\\b"

json_object *todo_from_note(const char *note) {
  if (!note || !*note || !g_regex_match(re(REMIND_PREFIX, 0), note, 0, NULL))
    return NULL;
  g_autofree char *rest = re_replace(REMIND_PREFIX, note, "");
  g_autofree char *title = strip_space(rest);
  g_autoptr(GDateTime) when = parse_when(note);
  g_autofree char *without_when = re_replace(TRAILING_WHEN, title, "");
  // Trim spaces and , . ; : - from both ends.
  const char *start = without_when;
  while (*start && strchr(" ,.;:-", *start))
    start++;
  g_autofree char *cleaned = g_strdup(start);
  for (size_t n = strlen(cleaned); n > 0 && strchr(" ,.;:-", cleaned[n - 1]); n--)
    cleaned[n - 1] = '\0';

  g_autofree char *chosen = strip_space(*cleaned ? cleaned : *title ? title : "Reminder");
  g_autofree char *due = when ? iso(when) : NULL;
  json_object *spec = json_object_new_object();
  json_object_object_add(spec, "title", json_object_new_string(chosen));
  json_object_object_add(spec, "due_at", json_str(due));
  json_object_object_add(spec, "suggested", json_object_new_boolean(false));   // asked for
  return spec;
}
