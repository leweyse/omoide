#include "omoide.h"

#include <gio/gio.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

void proc_result_clear(ProcResult *result) {
  g_clear_pointer(&result->out, g_free);
  g_clear_pointer(&result->err, g_free);
}

// Output is read as bytes and repaired rather than trusted to be UTF-8: it is
// whatever another program printed, and json-c refuses invalid UTF-8.
static char *text_of(const char *data, gsize size) {
  return g_utf8_make_valid(data ? data : "", (gssize)size);
}

static void exit_status(GSubprocess *child, ProcResult *result) {
  if (g_subprocess_get_if_exited(child))
    result->status = g_subprocess_get_exit_status(child);
  else if (g_subprocess_get_if_signaled(child))
    result->status = -g_subprocess_get_term_sig(child);
}

// --- proc_run: a short command, whole output

typedef struct {
  GMainLoop *loop;
  GBytes *out;
  GBytes *err;
  bool done;
  bool timed_out;
} Wait;

static void on_communicated(GObject *source, GAsyncResult *result, gpointer data) {
  Wait *wait = data;
  g_subprocess_communicate_finish(G_SUBPROCESS(source), result, &wait->out, &wait->err, NULL);
  wait->done = true;
  g_main_loop_quit(wait->loop);
}

static gboolean on_deadline(gpointer data) {
  Wait *wait = data;
  wait->timed_out = true;
  g_main_loop_quit(wait->loop);
  return G_SOURCE_REMOVE;
}

ProcResult proc_run(const char *const *argv, const char *input, double timeout_s) {
  ProcResult result = { .status = -1 };
  GSubprocessFlags flags = G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE;
  if (input)
    flags |= G_SUBPROCESS_FLAGS_STDIN_PIPE;

  g_autoptr(GError) error = NULL;
  g_autoptr(GSubprocess) child = g_subprocess_newv(argv, flags, &error);
  if (!child) {
    result.out = g_strdup("");
    result.err = g_strdup(error->message);
    return result;
  }
  result.started = true;

  // A context of our own, so waiting here never runs anything else's sources.
  g_autoptr(GMainContext) context = g_main_context_new();
  g_main_context_push_thread_default(context);
  Wait wait = { .loop = g_main_loop_new(context, FALSE) };

  g_autoptr(GBytes) stdin_bytes = input ? g_bytes_new(input, strlen(input)) : NULL;
  g_subprocess_communicate_async(child, stdin_bytes, NULL, on_communicated, &wait);

  GSource *timer = NULL;
  if (timeout_s > 0) {
    timer = g_timeout_source_new((guint)(timeout_s * 1000));
    g_source_set_callback(timer, on_deadline, &wait, NULL);
    g_source_attach(timer, context);
  }

  g_main_loop_run(wait.loop);
  if (!wait.done) {
    // Timed out: kill it, then let the pipes drain so nothing is left open.
    g_subprocess_force_exit(child);
    while (!wait.done)
      g_main_context_iteration(context, TRUE);
  }
  if (timer) {
    g_source_destroy(timer);
    g_source_unref(timer);
  }
  g_main_loop_unref(wait.loop);
  g_main_context_pop_thread_default(context);

  gsize size = 0;
  const char *data = wait.out ? g_bytes_get_data(wait.out, &size) : NULL;
  result.out = text_of(data, size);
  size = 0;
  data = wait.err ? g_bytes_get_data(wait.err, &size) : NULL;
  result.err = text_of(data, size);
  g_clear_pointer(&wait.out, g_bytes_unref);
  g_clear_pointer(&wait.err, g_bytes_unref);

  result.timed_out = wait.timed_out;
  if (!wait.timed_out)
    exit_status(child, &result);
  return result;
}

// --- proc_run_agent: capped, grouped, and killed as a group
//
// A capture-sized output would be read to EOF by a plain communicate: a
// provider that streams -- a wedged loop, JSONL events, a debug log left on --
// is bounded only by the timeout, and every byte is held in memory before
// anything looks at it. Here the cap is the ceiling and crossing it ends the
// run, because output that large is a malfunction and not an answer.

typedef struct {
  GMainContext *context;
  GCancellable *cancel;
  GByteArray *out;
  GByteArray *err;
  size_t cap;
  int streams_open;
  bool exited;
  bool over;
  bool timed_out;
} Agent;

typedef struct {
  Agent *agent;
  GInputStream *stream;
  GByteArray *sink;
} Reader;

static void read_next(Reader *reader);

static void on_chunk(GObject *source, GAsyncResult *result, gpointer data) {
  Reader *reader = data;
  Agent *agent = reader->agent;
  g_autoptr(GBytes) chunk = g_input_stream_read_bytes_finish(G_INPUT_STREAM(source), result, NULL);
  const gsize size = chunk ? g_bytes_get_size(chunk) : 0;
  if (size == 0) {
    agent->streams_open--;
    g_free(reader);
    return;
  }
  const size_t room = agent->cap > reader->sink->len ? agent->cap - reader->sink->len : 0;
  const guint8 *bytes = g_bytes_get_data(chunk, NULL);
  if (size > room) {
    // Flagged here, not on the next read: the chunk that crosses the cap can
    // also be the last one, and waiting for a read that never comes let a
    // truncated answer through as if the provider had printed bad JSON.
    g_byte_array_append(reader->sink, bytes, (guint)room);
    agent->over = true;
    agent->streams_open--;
    g_free(reader);
    return;
  }
  g_byte_array_append(reader->sink, bytes, (guint)size);
  read_next(reader);
}

static void read_next(Reader *reader) {
  g_input_stream_read_bytes_async(
      reader->stream, 65536, G_PRIORITY_DEFAULT, reader->agent->cancel, on_chunk, reader);
}

static void on_written(GObject *source, GAsyncResult *result, gpointer data) {
  (void)data;
  // A provider that never reads stdin, or exits first, is not an error here.
  g_output_stream_write_all_finish(G_OUTPUT_STREAM(source), result, NULL, NULL);
  g_output_stream_close(G_OUTPUT_STREAM(source), NULL, NULL);
}

static void on_exited(GObject *source, GAsyncResult *result, gpointer data) {
  Agent *agent = data;
  g_subprocess_wait_finish(G_SUBPROCESS(source), result, NULL);
  agent->exited = true;
}

static gboolean on_agent_deadline(gpointer data) {
  ((Agent *)data)->timed_out = true;
  return G_SOURCE_REMOVE;
}

// In the child, before exec: a group of its own, so a kill reaches whatever
// the agent itself started.
static void own_group(gpointer data) {
  (void)data;
  setpgid(0, 0);
}

static void kill_group(GSubprocess *child) {
  const char *id = g_subprocess_get_identifier(child);
  if (id)
    kill(-(pid_t)g_ascii_strtoll(id, NULL, 10), SIGKILL);
  g_subprocess_force_exit(child);
}

ProcResult proc_run_agent(const char *const *argv, const char *input, double timeout_s, const char *cwd,
    GHashTable *env, size_t cap) {
  ProcResult result = { .status = -1 };
  g_autoptr(GSubprocessLauncher) launcher = g_subprocess_launcher_new(
      G_SUBPROCESS_FLAGS_STDIN_PIPE | G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE);
  if (cwd)
    g_subprocess_launcher_set_cwd(launcher, cwd);
  if (env) {
    GHashTableIter iter;
    gpointer key, value;
    g_hash_table_iter_init(&iter, env);
    while (g_hash_table_iter_next(&iter, &key, &value))
      g_subprocess_launcher_setenv(launcher, key, value, TRUE);
  }
  g_subprocess_launcher_set_child_setup(launcher, own_group, NULL, NULL);

  g_autoptr(GMainContext) context = g_main_context_new();
  g_main_context_push_thread_default(context);

  g_autoptr(GError) error = NULL;
  g_autoptr(GSubprocess) child = g_subprocess_launcher_spawnv(launcher, argv, &error);
  if (!child) {
    g_main_context_pop_thread_default(context);
    result.out = g_strdup("");
    result.err = g_strdup(error->message);
    return result;
  }
  result.started = true;

  g_autoptr(GCancellable) cancel = g_cancellable_new();
  Agent agent = {
    .context = context,
    .cancel = cancel,
    .cap = cap,
    .streams_open = 2,
    .out = g_byte_array_new(),
    .err = g_byte_array_new(),
  };
  g_autoptr(GBytes) stdin_bytes = g_bytes_new(input ? input : "", input ? strlen(input) : 0);
  g_output_stream_write_all_async(g_subprocess_get_stdin_pipe(child), g_bytes_get_data(stdin_bytes, NULL),
      g_bytes_get_size(stdin_bytes), G_PRIORITY_DEFAULT, cancel, on_written, NULL);
  Reader *out = g_new0(Reader, 1);
  *out = (Reader){ &agent, g_subprocess_get_stdout_pipe(child), agent.out };
  Reader *err = g_new0(Reader, 1);
  *err = (Reader){ &agent, g_subprocess_get_stderr_pipe(child), agent.err };
  read_next(out);
  read_next(err);
  g_subprocess_wait_async(child, NULL, on_exited, &agent);

  GSource *timer = g_timeout_source_new((guint)(timeout_s * 1000));
  g_source_set_callback(timer, on_agent_deadline, &agent, NULL);
  g_source_attach(timer, context);

  while (!agent.exited) {
    g_main_context_iteration(context, TRUE);
    if (agent.over || agent.timed_out) {
      if (agent.over) {
        g_autofree char *limit = g_strdup_printf("%zu", cap);
        log_event("ai.capped", "cap", limit, NULL);
      }
      kill_group(child);
      while (!agent.exited)
        g_main_context_iteration(context, TRUE);
      break;
    }
  }

  // The process is gone; give the readers a moment for what is still in the
  // pipes, then stop -- a grandchild holding a pipe open must not hold us.
  const gint64 until = g_get_monotonic_time() + G_TIME_SPAN_SECOND;
  while (agent.streams_open > 0 && g_get_monotonic_time() < until)
    g_main_context_iteration(context, FALSE);
  g_cancellable_cancel(cancel);
  while (agent.streams_open > 0)
    g_main_context_iteration(context, TRUE);
  while (g_main_context_pending(context))
    g_main_context_iteration(context, FALSE);

  g_source_destroy(timer);
  g_source_unref(timer);
  g_main_context_pop_thread_default(context);

  result.out = text_of((const char *)agent.out->data, agent.out->len);
  result.err = text_of((const char *)agent.err->data, agent.err->len);
  g_byte_array_unref(agent.out);
  g_byte_array_unref(agent.err);
  result.capped = agent.over;
  result.timed_out = agent.timed_out && !agent.over;
  exit_status(child, &result);
  return result;
}

// --- helpers that run until stopped

GSubprocess *proc_spawn_quiet(const char *const *argv) {
  return g_subprocess_newv(argv, G_SUBPROCESS_FLAGS_STDOUT_SILENCE | G_SUBPROCESS_FLAGS_STDERR_SILENCE, NULL);
}

static void on_stopped(GObject *source, GAsyncResult *result, gpointer data) {
  g_subprocess_wait_finish(G_SUBPROCESS(source), result, NULL);
  *(bool *)data = true;
}

// Asked nicely, then told.
void proc_stop(GSubprocess *child, double grace_s) {
  if (!child)
    return;
  g_autoptr(GMainContext) context = g_main_context_new();
  g_main_context_push_thread_default(context);
  bool done = false;
  g_subprocess_send_signal(child, SIGTERM);
  g_subprocess_wait_async(child, NULL, on_stopped, &done);
  const gint64 until = g_get_monotonic_time() + (gint64)(grace_s * G_TIME_SPAN_SECOND);
  while (!done && g_get_monotonic_time() < until)
    if (!g_main_context_iteration(context, FALSE))
      g_usleep(10000);
  if (!done) {
    g_subprocess_force_exit(child);
    while (!done)
      g_main_context_iteration(context, TRUE);
  }
  g_main_context_pop_thread_default(context);
  g_object_unref(child);
}
