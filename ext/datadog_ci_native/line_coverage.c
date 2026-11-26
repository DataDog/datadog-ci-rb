#include <ruby.h>

#include "line_coverage.h"

/*
 * Per-test line coverage with one-shot traps.
 *
 * A line ran when any instruction the iseq line table maps to it ran. The sites of an
 * iseq in repository code are the first instruction of every run of instructions on one
 * line, plus every instruction inside such a run where control can enter other than by
 * falling through: a jump target, a catch table continuation, an optional-argument
 * entry. A site is armed by adding the trap event to the event flags of its insn-info
 * entry and switching its instruction to the trace variant, so the VM calls one hook
 * when it runs. The hook records the line for the context the running fiber
 * carries (a test, a suite fixture, or none), then disarms the site once every open
 * context has recorded it: it clears the trap event and restores the untraced
 * instruction unless the VM still dispatches another event there. Sites disarmed this
 * way are re-armed when a context opens and when the last open context closes, so code
 * that runs outside every context is recorded as unowned. Steady-state code runs
 * untraced; the cost is one trap per distinct (context, line). A line that runs with no
 * context while a context that already recorded it is open is not recorded as unowned.
 *
 * The trap event is RUBY_EVENT_COVERAGE_BRANCH, which only Ruby's branch coverage
 * uses. In code compiled under branch coverage, every instruction that is not a branch
 * gets an extra counter that Coverage never reports, so Ruby's branch hook stays harmless
 * on traps. Sites at branch targets are shared: Ruby keeps them traced, so the hook runs
 * on every execution there and returns early unless the site is armed.
 *
 * Initialiser code (a file's top level and the class and module bodies nested in it
 * through class and module bodies only) records into the file's initialiser lines once
 * per process and is never re-armed. For a repository file that finished loading before
 * the start, the collector compiles the file's source again without running it, and
 * records the lines of every initialiser iseq that must have run whole: one without
 * branches, held only by such iseqs.
 *
 * Code compiled by YJIT never runs trace instructions, so it would ignore re-armed
 * sites. From the first context on, while YJIT is on, every pc where YJIT can enter a
 * repository iseq holds a trace instruction (a guard), which keeps repository code
 * interpreted. Stopping the collector leaves the guards in place.
 *
 * Contexts reach other threads and fibers through fiber storage (Ruby 3.2+), which
 * Ruby copies into every thread and fiber a context creates.
 */

#if defined(DD_CI_LINE_COVERAGE) && defined(HAVE_RB_EXECUTION_CONTEXT_STORAGE)
#define DD_CI_LINE_COVERAGE_SUPPORTED 1
#endif

#ifndef DD_CI_LINE_COVERAGE_SUPPORTED

static VALUE supported_p(VALUE self) { return Qfalse; }

void Init_dd_ci_line_coverage(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mTIA = rb_define_module_under(mCI, "TestImpactAnalysis");
  VALUE mCoverage = rb_define_module_under(mTIA, "Coverage");
  VALUE mLineCollector = rb_define_module_under(mCoverage, "LineCollector");
  rb_define_singleton_method(mLineCollector, "supported?", supported_p, 0);
  rb_define_singleton_method(mLineCollector, "yjit_supported?", supported_p, 0);
}

#else

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wattributes"
#pragma GCC diagnostic ignored "-Wpragmas"
#pragma GCC diagnostic ignored "-Wexpansion-to-defined"
#include <vm_core.h>
#pragma GCC diagnostic pop

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
#include <iseq.h>
#pragma GCC diagnostic pop

#include <ruby/debug.h>
#include <ruby/version.h>

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Generated into insns_info.inc, which the private headers do not ship; exported by
 * libruby for debuggers. */
extern const uint8_t rb_vm_insn_len_info[];
extern const char rb_vm_insn_op_base[];
extern const unsigned short rb_vm_insn_op_offset[];

#define OPERAND_TYPE_ISEQ 'S'
#define OPERAND_TYPE_OFFSET 'O'
#define OPERAND_TYPE_CDHASH 'H'

/* Defined in internal/thread.h, which the private headers do not ship. */
#ifndef COVERAGE_INDEX_BRANCHES
#define COVERAGE_INDEX_BRANCHES 1
#endif

enum site_flag {
  SITE_INIT = 1 << 0,          /* initialiser code */
  SITE_ARMED = 1 << 1,         /* traps on its next execution */
  SITE_PLAIN_UNKNOWN = 1 << 2, /* already traced when found; untraced encoding unknown */
  SITE_DIRTY = 1 << 3,         /* disarmed, re-armed when the next context opens */
  SITE_INIT_SEEN = 1 << 4,     /* initialiser line recorded */
  SITE_ENTRY_FLAGGED = 1 << 5, /* we set the trap event in its entry */
  SITE_SHARED = 1 << 6,        /* Ruby's Coverage set the trap event in its entry */
  SITE_GUARD = 1 << 7,         /* keeps YJIT out of its iseq: never untraced */
};

typedef struct {
  VALUE *slot;  /* the instruction in iseq_encoded */
  VALUE plain;  /* encoding to restore on disarm */
  VALUE trace;  /* encoding that traps */
  struct iseq_insn_info_entry *entry;
  uint32_t pos;
  uint32_t record;
  uint32_t line;
  uint16_t insn;
  uint8_t flags;
} site_t;

/* Above any instruction number the VM defines; insns.inc is not shipped. */
#define INSN_TABLE_SIZE 512

typedef struct {
  const rb_iseq_t *iseq;
  uint32_t file;
  uint32_t first_site;
  uint32_t site_count;
  uint32_t first_guard;
  uint32_t guard_count;
  long guards_checked; /* serial of the context whose opening last checked the guards */
} iseq_record_t;

/* An armed iseq in the map, with what a trap needs next to the key: a trap then reads no
 * record, which would mostly miss the cache. */
typedef struct {
  uintptr_t iseq; /* 0: empty slot */
  uint32_t record;
  uint32_t file;
  uint32_t first_site;
  uint32_t site_count;
  uint32_t last_site; /* the last site that trapped: an iseq's lines mostly trap in order */
} armed_iseq_t;

/* A YJIT guard: a trace instruction at a pc where YJIT can enter an iseq. */
typedef struct {
  VALUE *slot;
  VALUE value;
} guard_t;

typedef struct {
  uint8_t *bytes;
  uint32_t length;
} line_bitmap_t;

typedef struct {
  VALUE path; /* repository-relative */
  line_bitmap_t init_lines;
  line_bitmap_t suite_setup_lines;
  line_bitmap_t scratch;
  /* initialiser lines of a file loaded before a start that may not have run */
  line_bitmap_t initialisers_left;
  uint32_t scratch_epoch;
  /* the collector saw the file load, or credited its initialisers at a start */
  bool initialisers_known;
} file_t;

/* A site a context recorded, with its file and line: reading a context back then touches
 * no site, which would mostly miss the cache. */
typedef struct {
  uint32_t site;
  uint32_t file;
  uint32_t line;
} hit_t;

typedef struct {
  long serial; /* 0: free slot */
  bool open;
  bool fixture;
  uint64_t *bits; /* one bit per site */
  hit_t *hits;    /* sites recorded, in order */
  size_t hit_count;
  size_t hit_capacity;
} context_t;

typedef struct {
  uint32_t *items;
  size_t count;
  size_t capacity;
} id_vector_t;

static struct {
  bool started;
  bool compile_hook_installed;
  bool trap_hook_installed;
  bool yjit_guarded; /* every armed iseq has its YJIT guards */
  VALUE root;          /* realpath of the repository root, with a trailing '/' */
  VALUE ignored_paths; /* realpath prefixes excluded on top of the dependency directories */
  VALUE path_cache;    /* iseq path -> file index (Integer) or false */
  VALUE files_by_path; /* repository-relative path -> file index (Integer) */
  VALUE context_key;   /* fiber storage key */
  VALUE compile_options; /* for compiling files loaded before the start */
  bool crediting_loaded_files;

  site_t *sites;
  size_t site_count;
  size_t site_capacity;
  /* each site's pos, by site index: searching them touches few cache lines */
  uint32_t *site_positions;
  size_t position_capacity;

  iseq_record_t *records;
  size_t record_count;
  size_t record_capacity;

  guard_t *guards;
  size_t guard_count;
  size_t guard_capacity;

  /* branch counter array -> index of the counter added for non-branch instructions */
  st_table *spare_counters;
  VALUE *spare_counter_arrays; /* kept alive and pinned: their addresses are table keys */
  size_t spare_counter_array_count;
  size_t spare_counter_array_capacity;

  /* open addressing by iseq pointer */
  armed_iseq_t *map;
  size_t map_capacity;
  size_t map_count;
  /* the last lookup, NULL entry for an iseq that is not armed; consecutive traps usually
   * come from one iseq */
  const rb_iseq_t *cached_iseq;
  armed_iseq_t *cached_entry;

  file_t *files;
  size_t file_count;
  size_t file_capacity;

  context_t *contexts;
  size_t context_count;
  size_t context_capacity;
  long next_serial;
  uint32_t *open_contexts;
  size_t open_count;
  size_t open_capacity;

  size_t bit_words; /* words in every site bitset */
  uint64_t *unowned_bits;
  id_vector_t unowned_hits;
  id_vector_t dirty;
  id_vector_t touched; /* files with lines in the record being built */
  uint32_t epoch;

  /* the GC count after the last event flag sync, and whether a GC was still running then */
  size_t gc_count_at_flag_sync;
  bool gc_running_at_flag_sync;

  /* untraced encoding by instruction number, learned while arming; 0 while unknown */
  VALUE plain_by_insn[INSN_TABLE_SIZE];
  size_t plain_known;

  struct {
    unsigned long hook_calls;
    unsigned long foreign_calls;
    unsigned long idle_calls;
    unsigned long iseqs_skipped;
    unsigned long guard_repairs;
    unsigned long yjit_invalidations;
    unsigned long entry_aliases;
    unsigned long traps;
    unsigned long init_traps;
    unsigned long unowned_traps;
    unsigned long kept_armed;
    unsigned long disarms;
    unsigned long rearms;
    unsigned long iseqs_armed;
    unsigned long iseqs_scanned;
    unsigned long allocation_failures;
    unsigned long event_flag_syncs;
    double discovery_seconds;
    unsigned long loaded_files; /* repository files loaded before a start, compiled again */
    unsigned long loaded_file_failures;
    unsigned long loaded_files_with_branches;
    unsigned long loaded_lines_credited;
    unsigned long loaded_lines_left;
    double loaded_files_seconds;
  } stats;
} st;

static VALUE state_holder = Qnil;

static inline file_t *site_file(const site_t *site) { return &st.files[st.records[site->record].file]; }

/* YJIT exists only in some builds, so its symbols are looked up at runtime. */
#if RUBY_API_VERSION_MAJOR == 3 && RUBY_API_VERSION_MINOR < 3
static bool (*yjit_enabled_function)(void);
#else
static const bool *yjit_enabled_variable;
#endif
static void (*yjit_invalidate_all)(void);

static bool yjit_enabled(void) {
#if RUBY_API_VERSION_MAJOR == 3 && RUBY_API_VERSION_MINOR < 3
  return yjit_enabled_function && yjit_enabled_function();
#else
  return yjit_enabled_variable && *yjit_enabled_variable;
#endif
}

/* ---- small containers --------------------------------------------------- */

static bool grow(void **items, size_t *capacity, size_t needed, size_t item_size) {
  if (needed <= *capacity) return true;
  size_t new_capacity = *capacity ? *capacity : 64;
  while (new_capacity < needed) new_capacity *= 2;
  void *grown = realloc(*items, new_capacity * item_size);
  if (!grown) {
    st.stats.allocation_failures++;
    return false;
  }
  *items = grown;
  *capacity = new_capacity;
  return true;
}

static bool id_vector_push(id_vector_t *vector, uint32_t id) {
  if (!grow((void **)&vector->items, &vector->capacity, vector->count + 1, sizeof(uint32_t))) return false;
  vector->items[vector->count++] = id;
  return true;
}

static inline bool bit_test(const uint64_t *bits, uint32_t id) { return (bits[id >> 6] >> (id & 63)) & 1; }

/* Sets the bit; returns whether it was already set. */
static inline bool bit_test_and_set(uint64_t *bits, uint32_t id) {
  uint64_t mask = (uint64_t)1 << (id & 63);
  bool was_set = (bits[id >> 6] & mask) != 0;
  bits[id >> 6] |= mask;
  return was_set;
}

static inline void bit_clear(uint64_t *bits, uint32_t id) { bits[id >> 6] &= ~((uint64_t)1 << (id & 63)); }

static bool line_bitmap_reserve(line_bitmap_t *bitmap, uint32_t length) {
  if (length <= bitmap->length) return true;
  uint32_t new_length = bitmap->length ? bitmap->length : 16;
  while (new_length < length) new_length *= 2;
  uint8_t *grown = realloc(bitmap->bytes, new_length);
  if (!grown) {
    st.stats.allocation_failures++;
    return false;
  }
  memset(grown + bitmap->length, 0, new_length - bitmap->length);
  bitmap->bytes = grown;
  bitmap->length = new_length;
  return true;
}

static bool line_bitmap_set(line_bitmap_t *bitmap, uint32_t line) {
  uint32_t byte = line >> 3;
  if (!line_bitmap_reserve(bitmap, byte + 1)) return false;
  /* Java order: bit (line & 7) of byte (line >> 3). */
  bitmap->bytes[byte] |= (uint8_t)(1 << (line & 7));
  return true;
}

static uint32_t line_bitmap_used_length(const line_bitmap_t *bitmap) {
  uint32_t length = bitmap->length;
  while (length > 0 && bitmap->bytes[length - 1] == 0) length--;
  return length;
}

static void line_bitmap_or(line_bitmap_t *target, const line_bitmap_t *source) {
  uint32_t length = line_bitmap_used_length(source);
  if (!line_bitmap_reserve(target, length)) return;
  for (uint32_t byte = 0; byte < length; byte++) target->bytes[byte] |= source->bytes[byte];
}

/* ---- iseq map ------------------------------------------------------------ */

static inline size_t map_slot(uintptr_t key, size_t capacity) {
  return (size_t)(((uint64_t)(key >> 4) * 11400714819323198485ull) >> 20) & (capacity - 1);
}

static armed_iseq_t *map_find(const rb_iseq_t *iseq) {
  if (!st.map_capacity) return NULL;
  uintptr_t key = (uintptr_t)iseq;
  size_t index = map_slot(key, st.map_capacity);
  for (;;) {
    armed_iseq_t *entry = &st.map[index];
    if (entry->iseq == key) return entry;
    if (entry->iseq == 0) return NULL;
    index = (index + 1) & (st.map_capacity - 1);
  }
}

static void map_insert_unchecked(const armed_iseq_t *armed) {
  size_t index = map_slot(armed->iseq, st.map_capacity);
  while (st.map[index].iseq != 0 && st.map[index].iseq != armed->iseq) index = (index + 1) & (st.map_capacity - 1);
  if (st.map[index].iseq == 0) st.map_count++;
  st.map[index] = *armed;
}

static bool map_put(const iseq_record_t *record, uint32_t record_index) {
  if ((st.map_count + 1) * 2 > st.map_capacity) {
    size_t old_capacity = st.map_capacity;
    armed_iseq_t *old_map = st.map;
    size_t new_capacity = old_capacity ? old_capacity * 2 : 4096;
    armed_iseq_t *map = calloc(new_capacity, sizeof(armed_iseq_t));
    if (!map) {
      st.stats.allocation_failures++;
      return false;
    }
    st.map = map;
    st.map_capacity = new_capacity;
    st.map_count = 0;
    for (size_t i = 0; i < old_capacity; i++) {
      if (old_map[i].iseq) map_insert_unchecked(&old_map[i]);
    }
    free(old_map);
  }
  armed_iseq_t armed = {
      .iseq = (uintptr_t)record->iseq,
      .record = record_index,
      .file = record->file,
      .first_site = record->first_site,
      .site_count = record->site_count,
      /* Wraps for the first site: the hint then names the first site. */
      .last_site = record->first_site - 1,
  };
  map_insert_unchecked(&armed);
  /* The cache may hold this address as unknown, or point into the old table. */
  st.cached_iseq = NULL;
  st.cached_entry = NULL;
  return true;
}

/* ---- encodings ------------------------------------------------------------ */

/* The VM only switches an instruction to its trace variant when its entry carries an
 * enabled event, so an instruction whose entry carries none shows its untraced encoding. */
static void plain_learn(VALUE insn, VALUE plain) {
  if (insn >= INSN_TABLE_SIZE || st.plain_by_insn[insn]) return;
  st.plain_by_insn[insn] = plain;
  st.plain_known++;
}

static bool plain_for(const site_t *site, VALUE *plain) {
  if (site->insn >= INSN_TABLE_SIZE || !st.plain_by_insn[site->insn]) return false;
  *plain = st.plain_by_insn[site->insn];
  return true;
}

/* ---- bitsets -------------------------------------------------------------- */

static bool resize_bitset(uint64_t **bits, size_t old_words, size_t new_words) {
  uint64_t *grown = realloc(*bits, new_words * sizeof(uint64_t));
  if (!grown) {
    st.stats.allocation_failures++;
    return false;
  }
  memset(grown + old_words, 0, (new_words - old_words) * sizeof(uint64_t));
  *bits = grown;
  return true;
}

/* Makes every site bitset hold `site_count` bits. */
static bool ensure_bit_capacity(size_t site_count) {
  size_t needed = (site_count + 63) / 64;
  if (needed <= st.bit_words) return true;
  size_t new_words = st.bit_words ? st.bit_words : 1024;
  while (new_words < needed) new_words *= 2;
  if (!resize_bitset(&st.unowned_bits, st.bit_words, new_words)) return false;
  for (size_t i = 0; i < st.context_count; i++) {
    context_t *context = &st.contexts[i];
    if (context->bits && !resize_bitset(&context->bits, st.bit_words, new_words)) return false;
  }
  st.bit_words = new_words;
  return true;
}

/* ---- files ---------------------------------------------------------------- */

static bool has_suffix(const char *string, size_t length, const char *suffix) {
  size_t suffix_length = strlen(suffix);
  return length >= suffix_length && memcmp(string + length - suffix_length, suffix, suffix_length) == 0;
}

/* The accuracy reference's file rule: a regular `.rb` file whose realpath is under the
 * repository root, with no dependency directory (vendor, node_modules, .bundle, gems)
 * on its path and no hidden directory. */
static long classify_path_uncached(VALUE path) {
  const char *raw = RSTRING_PTR(path);
  long raw_length = RSTRING_LEN(path);
  if (memchr(raw, 0, raw_length) != NULL) return -1;
  if (!has_suffix(raw, raw_length, ".rb")) return -1;

  char *real = realpath(StringValueCStr(path), NULL);
  if (!real) return -1;

  long result = -1;
  struct stat file_stat;
  const char *root = RSTRING_PTR(st.root);
  size_t root_length = RSTRING_LEN(st.root);
  size_t real_length = strlen(real);
  if (stat(real, &file_stat) != 0 || !S_ISREG(file_stat.st_mode)) goto done;
  if (real_length <= root_length || memcmp(real, root, root_length) != 0) goto done;

  for (long i = 0; i < RARRAY_LEN(st.ignored_paths); i++) {
    VALUE ignored = RARRAY_AREF(st.ignored_paths, i);
    size_t ignored_length = RSTRING_LEN(ignored);
    if (ignored_length > 0 && real_length >= ignored_length && memcmp(real, RSTRING_PTR(ignored), ignored_length) == 0) goto done;
  }

  const char *relative = real + root_length;
  const char *part = relative;
  while (*part) {
    const char *end = strchr(part, '/');
    size_t part_length = end ? (size_t)(end - part) : strlen(part);
    bool directory = end != NULL;
    if ((part_length == 6 && memcmp(part, "vendor", 6) == 0) ||
        (part_length == 12 && memcmp(part, "node_modules", 12) == 0) ||
        (part_length == 7 && memcmp(part, ".bundle", 7) == 0) ||
        (part_length == 4 && memcmp(part, "gems", 4) == 0)) {
      goto done;
    }
    if (directory && part_length > 0 && part[0] == '.') goto done;
    if (!end) break;
    part = end + 1;
  }

  /* A start after a stop classifies paths again; the file keeps its entry. */
  VALUE relative_path = rb_obj_freeze(rb_utf8_str_new_cstr(relative));
  VALUE known = rb_hash_lookup2(st.files_by_path, relative_path, Qundef);
  if (known != Qundef) {
    result = FIX2LONG(known);
    goto done;
  }
  size_t file_capacity = st.file_capacity;
  if (!grow((void **)&st.files, &file_capacity, st.file_count + 1, sizeof(file_t))) goto done;
  st.file_capacity = file_capacity;
  file_t *file = &st.files[st.file_count];
  memset(file, 0, sizeof(*file));
  file->path = relative_path;
  result = (long)st.file_count++;
  rb_hash_aset(st.files_by_path, relative_path, LONG2FIX(result));

done:
  free(real);
  return result;
}

static long classify_path(VALUE path) {
  if (!RB_TYPE_P(path, T_STRING)) return -1;
  VALUE cached = rb_hash_lookup2(st.path_cache, path, Qundef);
  if (cached != Qundef) return cached == Qfalse ? -1 : FIX2LONG(cached);
  long file = classify_path_uncached(path);
  rb_hash_aset(st.path_cache, rb_obj_freeze(rb_str_dup(path)), file < 0 ? Qfalse : LONG2FIX(file));
  return file;
}

/* Initialiser code is a file's top-level iseq and the class and module bodies nested in
 * it through class and module bodies only. Rescue and ensure clauses, which Ruby compiles
 * into iseqs of their own, belong to the code around them. A class body inside a method,
 * a block or an eval string is ordinary code. Nesting comes from the iseq that holds a
 * child in an operand or its catch table: singleton class bodies have no parent_iseq. */
static bool initialiser_root_p(const rb_iseq_t *iseq) {
  const struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);
  return body && (body->type == ISEQ_TYPE_TOP || body->type == ISEQ_TYPE_MAIN);
}

static bool initialiser_child_p(const rb_iseq_t *child, bool holder_initialiser) {
  const struct rb_iseq_constant_body *body = ISEQ_BODY(child);
  return holder_initialiser && body &&
         (body->type == ISEQ_TYPE_CLASS || body->type == ISEQ_TYPE_RESCUE || body->type == ISEQ_TYPE_ENSURE);
}

/* Iseqs waiting to be armed, each with whether it is initialiser code. */
typedef struct {
  const rb_iseq_t *iseq;
  bool initialiser;
} pending_iseq_t;

typedef struct {
  pending_iseq_t *items;
  size_t count;
  size_t capacity;
} pending_iseqs_t;

static void push_pending(pending_iseqs_t *pending, const rb_iseq_t *iseq, bool initialiser) {
  if (!grow((void **)&pending->items, &pending->capacity, pending->count + 1, sizeof(pending_iseq_t))) return;
  pending->items[pending->count].iseq = iseq;
  pending->items[pending->count].initialiser = initialiser;
  pending->count++;
}

/* Calls `callback` with every iseq that `iseq` holds in its catch table or an operand.
 * `original` is its instructions as instruction numbers. */
static void each_child(const rb_iseq_t *iseq, const VALUE *original, void (*callback)(const rb_iseq_t *, void *),
                       void *data) {
  const struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);
  if (body->catch_table) {
    for (unsigned int i = 0; i < body->catch_table->size; i++) {
      const struct iseq_catch_table_entry *entry = UNALIGNED_MEMBER_PTR(body->catch_table, entries[i]);
      if (entry->iseq) callback(entry->iseq, data);
    }
  }
  for (unsigned int pos = 0; pos < body->iseq_size;) {
    VALUE insn = original[pos];
    const char *types = &rb_vm_insn_op_base[rb_vm_insn_op_offset[insn]];
    for (int j = 0; types[j]; j++) {
      const rb_iseq_t *child = (const rb_iseq_t *)original[pos + j + 1];
      if (types[j] == OPERAND_TYPE_ISEQ && child) callback(child, data);
    }
    pos += rb_vm_insn_len_info[insn];
  }
}

typedef struct {
  pending_iseqs_t *pending;
  bool holder_initialiser;
} child_push_t;

static void push_child(const rb_iseq_t *child, void *data) {
  child_push_t *push = (child_push_t *)data;
  push_pending(push->pending, child, initialiser_child_p(child, push->holder_initialiser));
}

/* ---- the trap event --------------------------------------------------------- */

#define TRAP_EVENT RUBY_EVENT_COVERAGE_BRANCH

/* Whether the iseq was compiled under Ruby's branch coverage. */
static bool branch_coverage_p(const rb_iseq_t *iseq) {
  VALUE coverage = ISEQ_COVERAGE(iseq);
  return RB_TYPE_P(coverage, T_ARRAY) && RARRAY_LEN(coverage) > COVERAGE_INDEX_BRANCHES &&
         RTEST(RARRAY_AREF(coverage, COVERAGE_INDEX_BRANCHES));
}

/* Ruby's branch hook reads ISEQ_PC2BRANCHINDEX(iseq)[pc] for every instruction that
 * carries RUBY_EVENT_COVERAGE_BRANCH and counts into that branch counter; the array only
 * reaches the last branch. Points every other pc at a counter added to the file's
 * counters, which Coverage.result never reports, since it reads counters through its
 * branch structure. Returns false when the structures are not the expected ones. */
static bool add_spare_branch_counter(const rb_iseq_t *iseq) {
  VALUE branches = RARRAY_AREF(ISEQ_COVERAGE(iseq), COVERAGE_INDEX_BRANCHES);
  if (!RB_TYPE_P(branches, T_ARRAY) || RARRAY_LEN(branches) < 2) return false;
  VALUE counters = RARRAY_AREF(branches, 1);
  VALUE indexes = ISEQ_PC2BRANCHINDEX(iseq);
  if (!RB_TYPE_P(counters, T_ARRAY) || !RB_TYPE_P(indexes, T_ARRAY)) return false;

  st_data_t spare;
  if (!st_lookup(st.spare_counters, (st_data_t)counters, &spare)) {
    size_t capacity = st.spare_counter_array_capacity;
    if (!grow((void **)&st.spare_counter_arrays, &capacity, st.spare_counter_array_count + 1, sizeof(VALUE))) {
      return false;
    }
    st.spare_counter_array_capacity = capacity;
    st.spare_counter_arrays[st.spare_counter_array_count++] = counters;
    spare = (st_data_t)RARRAY_LEN(counters);
    rb_ary_push(counters, INT2FIX(0));
    st_insert(st.spare_counters, (st_data_t)counters, spare);
  }
  VALUE spare_index = LONG2FIX((long)spare);
  long size = (long)ISEQ_BODY(iseq)->iseq_size;
  for (long pc = 0; pc < RARRAY_LEN(indexes) && pc < size; pc++) {
    if (NIL_P(RARRAY_AREF(indexes, pc))) RARRAY_ASET(indexes, pc, spare_index);
  }
  while (RARRAY_LEN(indexes) < size) rb_ary_push(indexes, spare_index);
  return true;
}

/* ---- arming --------------------------------------------------------------- */

static bool add_site(uint32_t pos, struct iseq_insn_info_entry *entry, uint32_t record, uint32_t line, uint8_t flags) {
  size_t capacity = st.site_capacity;
  if (!grow((void **)&st.sites, &capacity, st.site_count + 1, sizeof(site_t))) return false;
  st.site_capacity = capacity;
  size_t position_capacity = st.position_capacity;
  if (!grow((void **)&st.site_positions, &position_capacity, st.site_count + 1, sizeof(uint32_t))) return false;
  st.position_capacity = position_capacity;
  st.site_positions[st.site_count] = pos;
  site_t *site = &st.sites[st.site_count++];
  memset(site, 0, sizeof(*site));
  site->pos = pos;
  site->entry = entry;
  site->record = record;
  site->line = line;
  site->flags = flags;
  return true;
}

static void guard_iseq(iseq_record_t *record);

typedef struct {
  uint8_t *entry_point;
  long size;
  long base;
} case_targets_t;

static int mark_case_target(VALUE key, VALUE value, VALUE data) {
  case_targets_t *targets = (case_targets_t *)data;
  if (FIXNUM_P(value)) {
    long target = targets->base + FIX2LONG(value);
    if (target >= 0 && target < targets->size) targets->entry_point[target] = 1;
  }
  return ST_CONTINUE;
}

/* Marks the instructions control can reach other than by falling through from the
 * previous one: pc 0, optional-argument entries, catch table continuations, and the
 * targets of jumps, branches and case dispatch. */
static void mark_entry_points(const struct rb_iseq_constant_body *body, const VALUE *original, uint8_t *entry_point) {
  long size = (long)body->iseq_size;
  entry_point[0] = 1;
  if (body->param.flags.has_opt) {
    for (int i = 0; i <= body->param.opt_num; i++) {
      long pc = (long)body->param.opt_table[i];
      if (pc >= 0 && pc < size) entry_point[pc] = 1;
    }
  }
  if (body->catch_table) {
    for (unsigned int i = 0; i < body->catch_table->size; i++) {
      long cont = (long)UNALIGNED_MEMBER_PTR(body->catch_table, entries[i])->cont;
      if (cont < size) entry_point[cont] = 1;
    }
  }
  for (long pos = 0; pos < size;) {
    VALUE insn = original[pos];
    long length = rb_vm_insn_len_info[insn];
    const char *types = &rb_vm_insn_op_base[rb_vm_insn_op_offset[insn]];
    for (int j = 0; types[j]; j++) {
      VALUE operand = original[pos + j + 1];
      if (types[j] == OPERAND_TYPE_OFFSET) {
        long target = pos + length + (long)(SIGNED_VALUE)operand;
        if (target >= 0 && target < size) entry_point[target] = 1;
      } else if (types[j] == OPERAND_TYPE_CDHASH && RB_TYPE_P(operand, T_HASH)) {
        case_targets_t targets = {entry_point, size, pos + length};
        rb_hash_foreach(operand, mark_case_target, (VALUE)&targets);
      }
    }
    pos += length;
  }
}

/* Finds the sites of `iseq`, registers them, and arms them. Pushes the child iseqs onto
 * `nested` when given. */
static void arm_iseq(const rb_iseq_t *iseq, long file, bool initialiser, pending_iseqs_t *nested) {
  struct rb_iseq_constant_body *body = (struct rb_iseq_constant_body *)ISEQ_BODY(iseq);
  st.stats.iseqs_scanned++;
  if (!body || body->iseq_size == 0 || !ISEQ_EXECUTABLE_P(iseq)) return;

  bool had_original = ISEQ_ORIGINAL_ISEQ(iseq) != NULL;
  VALUE *original = rb_iseq_original_iseq(iseq);

  if (nested) {
    child_push_t push = {nested, initialiser};
    each_child(iseq, original, push_child, &push);
  }

  if (file < 0 || map_find(iseq)) goto done;

  unsigned int entry_count = body->insns_info.size;
  struct iseq_insn_info_entry *entries = (struct iseq_insn_info_entry *)body->insns_info.body;
  if (entry_count == 0 || !entries) goto done;

  /* A script without code, such as an empty file, compiles to instructions without
   * events, and no line of it runs, so it gets no sites. Other iseqs without events keep
   * theirs: before Ruby 3.3, an empty rescue clause has no events, yet its line runs. */
  if (body->type == ISEQ_TYPE_TOP || body->type == ISEQ_TYPE_MAIN || body->type == ISEQ_TYPE_EVAL) {
    bool has_events = false;
    for (unsigned int k = 0; k < entry_count && !has_events; k++) has_events = entries[k].events != 0;
    if (!has_events) goto done;
  }

  if (branch_coverage_p(iseq) && !add_spare_branch_counter(iseq)) {
    st.stats.iseqs_skipped++;
    goto done;
  }
  uint8_t base_flags = SITE_ARMED | (initialiser ? SITE_INIT : 0);

  unsigned int size = body->iseq_size;
  int *lines = malloc(entry_count * sizeof(int));
  uint8_t *entry_point = calloc(size, 1);
  VALUE *before = malloc(size * sizeof(VALUE));
  if (!lines || !entry_point || !before) {
    st.stats.allocation_failures++;
    free(lines);
    free(entry_point);
    free(before);
    goto done;
  }
  mark_entry_points(body, original, entry_point);

  /* rb_iseq_line_no(iseq, pos) returns the line of the entry covering pos; numbering
   * the entries first turns it into the entry lookup, whatever the table encoding. No
   * Ruby code runs while the numbers are swapped. */
  for (unsigned int k = 0; k < entry_count; k++) {
    lines[k] = entries[k].line_no;
    entries[k].line_no = (int)k + 1;
  }

  VALUE *encoded = (VALUE *)body->iseq_encoded;
  size_t first = st.site_count;
  int previous_line = 0;
  for (unsigned int pos = 0; pos < size;) {
    VALUE insn = original[pos];
    unsigned int k = rb_iseq_line_no(iseq, pos);
    int line = 0;
    if (k >= 1 && k <= entry_count) {
      line = lines[k - 1];
      if (entries[k - 1].events == 0) plain_learn(insn, encoded[pos]);
    }
    if (line > 0 && insn < INSN_TABLE_SIZE && (line != previous_line || entry_point[pos])) {
      if (!add_site(pos, &entries[k - 1], (uint32_t)st.record_count, (uint32_t)line, base_flags)) break;
      st.sites[st.site_count - 1].insn = (uint16_t)insn;
    }
    previous_line = line;
    pos += rb_vm_insn_len_info[insn];
  }
  for (unsigned int k = 0; k < entry_count; k++) entries[k].line_no = lines[k];
  free(lines);
  free(entry_point);

  size_t count = st.site_count - first;
  size_t record_capacity = st.record_capacity;
  if (count == 0 || !ensure_bit_capacity(st.site_count) ||
      !grow((void **)&st.records, &record_capacity, st.record_count + 1, sizeof(iseq_record_t))) {
    st.site_count = first;
    free(before);
    goto done;
  }
  st.record_capacity = record_capacity;

  for (size_t i = first; i < st.site_count; i++) {
    site_t *site = &st.sites[i];
    site->slot = &encoded[site->pos];
    site->plain = *site->slot;
    if (i > first && st.sites[i - 1].entry == site->entry) st.stats.entry_aliases++;
    if (site->entry->events & TRAP_EVENT) site->flags |= SITE_SHARED;
  }
  for (size_t i = first; i < st.site_count; i++) {
    site_t *site = &st.sites[i];
    if (site->flags & SITE_SHARED) continue;
    site->entry->events |= TRAP_EVENT;
    site->flags |= SITE_ENTRY_FLAGGED;
  }

  /* Let the VM switch the flagged instructions to their trace variants. It keeps every
   * instruction that is already traced, and traces every instruction a flagged entry
   * covers, which can include instructions that are not sites: those are put back. */
  memcpy(before, encoded, size * sizeof(VALUE));
  rb_iseq_t *mutable_iseq = (rb_iseq_t *)iseq;
  rb_event_flag_t global_events = mutable_iseq->aux.exec.global_trace_events;
  mutable_iseq->aux.exec.global_trace_events = 0;
  rb_iseq_trace_set(iseq, global_events | TRAP_EVENT);
  size_t next_site = first;
  for (unsigned int pos = 0; pos < size;) {
    if (next_site < st.site_count && st.sites[next_site].pos == pos) {
      next_site++;
    } else if (encoded[pos] != before[pos]) {
      encoded[pos] = before[pos];
    }
    pos += rb_vm_insn_len_info[original[pos]];
  }
  free(before);

  for (size_t i = first; i < st.site_count; i++) {
    site_t *site = &st.sites[i];
    site->trace = *site->slot;
    if (site->trace != site->plain) {
      plain_learn(site->insn, site->plain);
    } else if (!plain_for(site, &site->plain)) {
      site->flags |= SITE_PLAIN_UNKNOWN;
    }
  }

  iseq_record_t *record = &st.records[st.record_count];
  memset(record, 0, sizeof(*record));
  record->iseq = iseq;
  record->file = (uint32_t)file;
  record->first_site = (uint32_t)first;
  record->site_count = (uint32_t)count;
  if (!map_put(record, (uint32_t)st.record_count)) {
    /* Leave the instructions armed but unknown to the hook; it ignores them. */
    st.site_count = first;
    goto done;
  }
  st.record_count++;
  st.stats.iseqs_armed++;
  if (st.yjit_guarded) guard_iseq(record);

done:
  if (!had_original) ISEQ_ORIGINAL_ISEQ_CLEAR(iseq);
}

/* Arms an iseq and everything nested in it. */
static void arm_tree(const rb_iseq_t *top) {
  pending_iseqs_t pending = {0};
  push_pending(&pending, top, initialiser_root_p(top));
  while (pending.count > 0) {
    pending_iseq_t next = pending.items[--pending.count];
    if (map_find(next.iseq)) continue;
    long file = classify_path(rb_iseq_path(next.iseq));
    if (file < 0) continue; /* nested code shares its parent's file */
    arm_iseq(next.iseq, file, next.initialiser, &pending);
  }
  free(pending.items);
}

/* ---- the hook ------------------------------------------------------------- */

static context_t *context_by_serial(long serial) {
  for (size_t i = 0; i < st.context_count; i++) {
    if (st.contexts[i].serial == serial) return &st.contexts[i];
  }
  return NULL;
}

static inline context_t *context_for(const rb_execution_context_t *ec) {
  VALUE storage = ec->storage;
  if (!RB_TYPE_P(storage, T_HASH)) return NULL;
  VALUE token = rb_hash_lookup2(storage, st.context_key, Qnil);
  if (!FIXNUM_P(token)) return NULL;
  context_t *context = context_by_serial(FIX2LONG(token));
  return context && context->open ? context : NULL;
}

/* The events targeted TracePoints enabled on the iseq. */
static rb_event_flag_t local_hook_events(const rb_iseq_t *iseq) {
#if RUBY_API_VERSION_MAJOR >= 4
  /* Ruby 4 keeps an iseq's targeted hooks per ractor, behind a function libruby does
   * not export: assume they need every event. */
  return iseq->aux.exec.local_hooks_cnt ? RUBY_EVENT_TRACEPOINT_ALL : 0;
#else
  return iseq->aux.exec.local_hooks ? iseq->aux.exec.local_hooks->events : 0;
#endif
}

/* Restores the untraced instruction unless the VM may still dispatch an event there. The
 * test is Ruby's own when it clears an event flag: once an event has been enabled, Ruby
 * relies on the instructions that carry it staying traced. The trap event does not count:
 * in the entry of a site that is not shared it is ours, and it stays set while another
 * site of the same entry is armed. */
static void untrace_if_unneeded(site_t *site, const rb_iseq_t *iseq) {
  if ((site->flags & SITE_GUARD) || *site->slot != site->trace) return;
  rb_event_flag_t needed = iseq->aux.exec.global_trace_events | local_hook_events(iseq);
  if (site->entry->events & needed & ~TRAP_EVENT) return;
  if (site->flags & SITE_PLAIN_UNKNOWN) {
    if (!plain_for(site, &site->plain)) return;
    site->flags &= ~SITE_PLAIN_UNKNOWN;
  }
  *site->slot = site->plain;
}

/* Whether another site of the same insn-info entry is armed. Sites of one entry are
 * adjacent: entries cover consecutive instructions, sites are ordered by position, and
 * the sites of other iseqs point into other tables. */
static bool entry_armed_elsewhere(const site_t *site) {
  size_t index = (size_t)(site - st.sites);
  for (size_t i = index; i > 0 && st.sites[i - 1].entry == site->entry; i--) {
    if (st.sites[i - 1].flags & SITE_ARMED) return true;
  }
  for (size_t i = index + 1; i < st.site_count && st.sites[i].entry == site->entry; i++) {
    if (st.sites[i].flags & SITE_ARMED) return true;
  }
  return false;
}

/* Returns whether the site was armed. A shared site stays traced for Ruby's Coverage;
 * the hook ignores it until it is armed again. */
static bool disarm(site_t *site, const rb_iseq_t *iseq) {
  if (!(site->flags & SITE_ARMED)) return false;
  site->flags &= ~SITE_ARMED;
  st.stats.disarms++;
  if (site->flags & SITE_SHARED) return true;
  if (site->flags & SITE_ENTRY_FLAGGED) {
    if (!entry_armed_elsewhere(site)) site->entry->events &= ~TRAP_EVENT;
    site->flags &= ~SITE_ENTRY_FLAGGED;
  }
  untrace_if_unneeded(site, iseq);
  return true;
}

static void arm(site_t *site) {
  if (site->flags & SITE_ARMED) return;
  site->flags |= SITE_ARMED;
  if (site->flags & SITE_SHARED) return;
  if (!(site->flags & SITE_ENTRY_FLAGGED)) {
    site->entry->events |= TRAP_EVENT;
    site->flags |= SITE_ENTRY_FLAGGED;
  }
  *site->slot = site->trace;
}

/* Sites of one iseq are ordered by position. */
static long find_site_between(uint32_t first_site, uint32_t site_count, uint32_t pos) {
  long low = first_site, high = (long)first_site + site_count - 1;
  while (low <= high) {
    long middle = (low + high) >> 1;
    uint32_t current = st.site_positions[middle];
    if (current == pos) return middle;
    if (current < pos) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return -1;
}

static long find_site(const iseq_record_t *record, uint32_t pos) {
  return find_site_between(record->first_site, record->site_count, pos);
}

/* Tries the site after the iseq's last trap first. */
static long find_trapped_site(const armed_iseq_t *armed, uint32_t pos) {
  uint32_t next = armed->last_site + 1;
  if (next >= armed->first_site && next < armed->first_site + armed->site_count && st.site_positions[next] == pos) {
    return next;
  }
  return find_site_between(armed->first_site, armed->site_count, pos);
}

/* ---- YJIT ------------------------------------------------------------------- */

/* YJIT compiles from the instruction where the interpreter enters an iseq and stops at
 * the first trace instruction, which it cannot compile. A trace instruction at every
 * such pc keeps the iseq interpreted, where re-armed traps take effect. The entries are
 * pc 0, each optional-argument entry, and each catch table continuation. Guarding again
 * rewrites the same pcs. */
static void guard_iseq(iseq_record_t *record) {
  const rb_iseq_t *iseq = record->iseq;
  const struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);
  unsigned int entry_count = body->insns_info.size;
  struct iseq_insn_info_entry *entries = (struct iseq_insn_info_entry *)body->insns_info.body;
  if (entry_count == 0 || !entries) return;

  size_t opt_count = body->param.flags.has_opt ? (size_t)body->param.opt_num + 1 : 0;
  size_t catch_count = body->catch_table ? body->catch_table->size : 0;
  size_t pc_count = 0;
  unsigned int size = body->iseq_size;
  unsigned int *pcs = malloc((1 + opt_count + catch_count) * sizeof(unsigned int));
  int *lines = malloc(entry_count * sizeof(int));
  bool *flagged = calloc(entry_count, sizeof(bool));
  uint8_t *guard_pc = calloc(size, 1);
  VALUE *before = malloc(size * sizeof(VALUE));
  if (!pcs || !lines || !flagged || !guard_pc || !before) {
    st.stats.allocation_failures++;
    goto done;
  }
  pcs[pc_count++] = 0;
  for (size_t i = 0; i < opt_count; i++) pcs[pc_count++] = (unsigned int)body->param.opt_table[i];
  for (size_t i = 0; i < catch_count; i++) {
    unsigned int cont = UNALIGNED_MEMBER_PTR(body->catch_table, entries[i])->cont;
    if (cont < body->iseq_size) pcs[pc_count++] = cont;
  }

  for (unsigned int k = 0; k < entry_count; k++) {
    lines[k] = entries[k].line_no;
    entries[k].line_no = (int)k + 1;
  }
  bool retrace = false;
  for (size_t i = 0; i < pc_count; i++) {
    unsigned int pc = pcs[i];
    guard_pc[pc] = 1;
    long site_index = find_site(record, pc);
    if (site_index >= 0) {
      site_t *site = &st.sites[site_index];
      site->flags |= SITE_GUARD;
      *site->slot = site->trace;
      continue;
    }
    /* Not a site: let the VM trace it through a passing event flag. */
    unsigned int k = rb_iseq_line_no(iseq, pc);
    if (k < 1 || k > entry_count) continue;
    if (!(entries[k - 1].events & TRAP_EVENT)) {
      entries[k - 1].events |= TRAP_EVENT;
      flagged[k - 1] = true;
    }
    retrace = true;
  }
  for (unsigned int k = 0; k < entry_count; k++) entries[k].line_no = lines[k];

  VALUE *encoded = (VALUE *)body->iseq_encoded;
  if (retrace) {
    memcpy(before, encoded, size * sizeof(VALUE));
    rb_iseq_t *mutable_iseq = (rb_iseq_t *)iseq;
    rb_event_flag_t global_events = mutable_iseq->aux.exec.global_trace_events;
    mutable_iseq->aux.exec.global_trace_events = 0;
    rb_iseq_trace_set(iseq, global_events | TRAP_EVENT);
    for (unsigned int k = 0; k < entry_count; k++) {
      if (flagged[k]) entries[k].events &= ~TRAP_EVENT;
    }
    /* The VM traced every instruction of each entry that carries the trap event, armed
     * sites' entries included: only the guards keep the change. */
    bool had_original = ISEQ_ORIGINAL_ISEQ(iseq) != NULL;
    VALUE *original = rb_iseq_original_iseq(iseq);
    for (unsigned int pos = 0; pos < size;) {
      if (!guard_pc[pos] && encoded[pos] != before[pos]) encoded[pos] = before[pos];
      pos += rb_vm_insn_len_info[original[pos]];
    }
    if (!had_original) ISEQ_ORIGINAL_ISEQ_CLEAR(iseq);
  }

  if (record->guard_count == 0) {
    size_t capacity = st.guard_capacity;
    if (!grow((void **)&st.guards, &capacity, st.guard_count + pc_count, sizeof(guard_t))) goto done;
    st.guard_capacity = capacity;
    record->first_guard = (uint32_t)st.guard_count;
    record->guard_count = (uint32_t)pc_count;
    st.guard_count += pc_count;
  }
  /* What each pc holds now, to notice when Ruby untraces it. */
  for (size_t i = 0; i < pc_count && i < record->guard_count; i++) {
    guard_t *guard = &st.guards[record->first_guard + i];
    guard->slot = &encoded[pcs[i]];
    guard->value = encoded[pcs[i]];
  }

done:
  free(pcs);
  free(lines);
  free(flagged);
  free(guard_pc);
  free(before);
}

static void invalidate_yjit_code(void) {
  if (!yjit_invalidate_all) return;
  yjit_invalidate_all();
  st.stats.yjit_invalidations++;
}

static void enable_yjit_guards(void) {
  for (size_t i = 0; i < st.record_count; i++) guard_iseq(&st.records[i]);
  st.yjit_guarded = true;
  /* Drops what YJIT compiled before the guards. */
  invalidate_yjit_code();
}

/* Removing a targeted TracePoint makes Ruby recompute the iseq's trace instructions,
 * which untraces guards at pcs whose events it no longer needs; YJIT may have compiled
 * the iseq since. Returns whether the guards had to be restored. */
static bool repair_guards(iseq_record_t *record) {
  if (record->guards_checked == st.next_serial) return false;
  record->guards_checked = st.next_serial;
  for (uint32_t i = 0; i < record->guard_count; i++) {
    const guard_t *guard = &st.guards[record->first_guard + i];
    if (*guard->slot != guard->value) {
      guard_iseq(record);
      st.stats.guard_repairs++;
      return true;
    }
  }
  return false;
}

/* ---- the trap ----------------------------------------------------------------- */

static void on_trap(const rb_trace_arg_t *trace_arg) {
  st.stats.hook_calls++;
  const rb_control_frame_t *cfp = trace_arg->cfp;
  const rb_iseq_t *iseq = cfp->iseq;
  armed_iseq_t *armed;
  if (iseq == st.cached_iseq) {
    armed = st.cached_entry;
  } else {
    armed = map_find(iseq);
    st.cached_iseq = iseq;
    st.cached_entry = armed;
  }
  if (!armed) {
    st.stats.foreign_calls++;
    return;
  }
  /* The VM advanced pc past the instruction before calling hooks. */
  long pos = (long)(cfp->pc - ISEQ_BODY(iseq)->iseq_encoded) - 1;
  long site_index = find_trapped_site(armed, (uint32_t)pos);
  if (site_index < 0) {
    st.stats.foreign_calls++;
    return;
  }
  armed->last_site = (uint32_t)site_index;
  site_t *site = &st.sites[site_index];
  if (!(site->flags & SITE_ARMED)) {
    st.stats.idle_calls++;
    /* Ruby traces it again when it recomputes the iseq's trace instructions. */
    if (!(site->flags & SITE_SHARED)) untrace_if_unneeded(site, iseq);
    return;
  }
  st.stats.traps++;

  if (site->flags & SITE_INIT) {
    st.stats.init_traps++;
    if (!(site->flags & SITE_INIT_SEEN)) {
      site->flags |= SITE_INIT_SEEN;
      line_bitmap_set(&site_file(site)->init_lines, site->line);
    }
    disarm(site, iseq);
    return;
  }

  uint32_t id = (uint32_t)site_index;
  context_t *context = context_for(trace_arg->ec);
  if (context) {
    if (!bit_test_and_set(context->bits, id)) {
      if (!grow((void **)&context->hits, &context->hit_capacity, context->hit_count + 1, sizeof(hit_t))) {
        /* Stays armed, so the next execution tries again. */
        bit_clear(context->bits, id);
        return;
      }
      context->hits[context->hit_count++] = (hit_t){id, armed->file, site->line};
    }
  } else {
    st.stats.unowned_traps++;
    if (!bit_test_and_set(st.unowned_bits, id) && !id_vector_push(&st.unowned_hits, id)) {
      bit_clear(st.unowned_bits, id);
      return;
    }
  }

  for (size_t i = 0; i < st.open_count; i++) {
    if (!bit_test(st.contexts[st.open_contexts[i]].bits, id)) {
      st.stats.kept_armed++;
      return;
    }
  }
  if (disarm(site, iseq) && !(site->flags & SITE_DIRTY)) {
    site->flags |= SITE_DIRTY;
    id_vector_push(&st.dirty, id);
  }
}


static void on_script_compiled(VALUE data, const rb_trace_arg_t *trace_arg) {
  /* What the collector compiles itself never runs. */
  if (st.crediting_loaded_files) return;
  VALUE compiled = trace_arg->data;
  if (RB_TYPE_P(compiled, T_ARRAY)) compiled = RARRAY_AREF(compiled, 1);
  if (!RB_TYPE_P(compiled, T_IMEMO) || imemo_type(compiled) != imemo_iseq) return;
  const rb_iseq_t *iseq = (const rb_iseq_t *)compiled;
  VALUE gc_was_disabled = rb_gc_disable();
  arm_tree(iseq);
  if (gc_was_disabled == Qfalse) rb_gc_enable();
  /* The file loads now, so its initialiser lines trap. */
  if (initialiser_root_p(iseq)) {
    long file = classify_path(rb_iseq_path(iseq));
    if (file >= 0) st.files[file].initialisers_known = true;
  }
}

static void on_event(VALUE data, const rb_trace_arg_t *trace_arg) {
  if (trace_arg->event & TRAP_EVENT) {
    on_trap(trace_arg);
  } else {
    on_script_compiled(data, trace_arg);
  }
}

#define HOOK_FLAGS (RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG)

/* A hook in Ruby's hook list, as vm_trace.c defines it from Ruby 2.7 to 4.0. */
typedef struct event_hook {
  rb_event_hook_flag_t hook_flags;
  rb_event_flag_t events;
  rb_event_hook_func_t func;
  VALUE data;
  struct event_hook *next;
  struct {
    rb_thread_t *th;
    unsigned int target_line;
  } filter;
} event_hook_t;

/* Every event Ruby's Coverage fires walks the whole hook list, so with SimpleCov each
 * hook costs a few nanoseconds per executed line. Ruby refuses one hook for an internal
 * event, the trap, and a normal one, script_compiled, though it dispatches both through
 * the same list: the compile event joins the trap hook once Ruby has linked it. Returns
 * false, changing nothing, unless the head of the list is that hook. */
static bool add_compile_event_to_trap_hook(void) {
  /* Where Ruby linked the hook. GET_EC() needs a symbol that libruby does not export. */
  const rb_thread_t *thread = (const rb_thread_t *)RTYPEDDATA_DATA(rb_thread_current());
  if (!thread || !thread->ec) return false;
  rb_hook_list_t *list = rb_ec_ractor_hooks(thread->ec);
  event_hook_t *hook = (event_hook_t *)list->hooks;
  if (!hook || hook->func != (rb_event_hook_func_t)on_event || hook->data != Qnil || hook->events != TRAP_EVENT ||
      hook->hook_flags != HOOK_FLAGS || hook->filter.th != NULL || hook->filter.target_line != 0) {
    return false;
  }
  hook->events |= RUBY_EVENT_SCRIPT_COMPILED;
  list->events |= RUBY_EVENT_SCRIPT_COMPILED;
  return true;
}

/* ---- discovery of loaded code ---------------------------------------------- */

typedef struct {
  const rb_iseq_t **items;
  size_t count;
  size_t capacity;
} iseq_list_t;

static int collect_iseqs(void *start, void *end, size_t stride, void *data) {
  iseq_list_t *list = (iseq_list_t *)data;
  for (VALUE v = (VALUE)start; v != (VALUE)end; v += stride) {
    if (RBASIC(v)->flags == 0 || BUILTIN_TYPE(v) != T_IMEMO || imemo_type(v) != imemo_iseq) continue;
    if (!grow((void **)&list->items, &list->capacity, list->count + 1, sizeof(rb_iseq_t *))) return 1;
    list->items[list->count++] = (const rb_iseq_t *)v;
  }
  return 0;
}

static double now_seconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void add_to_set(const rb_iseq_t *child, void *set) { st_insert((st_table *)set, (st_data_t)child, 1); }

/* Arms repository code loaded before the start from its outermost live iseqs, so that
 * each nested iseq knows whether it is initialiser code. An iseq whose holder was
 * collected can only run again if it is a method or a block, which are never
 * initialiser code. */
static void arm_loaded_code(void) {
  iseq_list_t list = {0};
  rb_objspace_each_objects(collect_iseqs, &list);
  st_table *nested = st_init_numtable();
  size_t repository_count = 0;
  for (size_t i = 0; i < list.count; i++) {
    const rb_iseq_t *iseq = list.items[i];
    if (classify_path(rb_iseq_path(iseq)) < 0) continue;
    list.items[repository_count++] = iseq;
    const struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);
    if (!body || body->iseq_size == 0 || !ISEQ_EXECUTABLE_P(iseq)) continue;
    bool had_original = ISEQ_ORIGINAL_ISEQ(iseq) != NULL;
    each_child(iseq, rb_iseq_original_iseq(iseq), add_to_set, nested);
    if (!had_original) ISEQ_ORIGINAL_ISEQ_CLEAR(iseq);
  }
  for (size_t i = 0; i < repository_count; i++) {
    if (!st_is_member(nested, (st_data_t)list.items[i])) arm_tree(list.items[i]);
  }
  st_free_table(nested);
  free(list.items);
}

/* ---- initialisers of files loaded before the start -------------------------- */

/* Instruction numbers from RubyVM::INSTRUCTION_NAMES; -1 when not found. */
static long insn_leave = -1;
static long insn_throw = -1;
static ID id_compile;

/* Whether `iseq`, once it starts, runs each of its instructions in order up to its last
 * one, unless it raises: no jump or branch, no throw, no leave before the last
 * instruction, and no catch table entry but break. A break entry continues right after
 * the call whose block breaks. */
static bool runs_whole_p(const rb_iseq_t *iseq, const VALUE *original) {
  const struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);
  if (body->catch_table) {
    for (unsigned int i = 0; i < body->catch_table->size; i++) {
      if (UNALIGNED_MEMBER_PTR(body->catch_table, entries[i])->type != CATCH_TYPE_BREAK) return false;
    }
  }
  for (unsigned int pos = 0; pos < body->iseq_size;) {
    VALUE insn = original[pos];
    unsigned int length = rb_vm_insn_len_info[insn];
    if ((long)insn == insn_throw || ((long)insn == insn_leave && pos + length < body->iseq_size)) return false;
    const char *types = &rb_vm_insn_op_base[rb_vm_insn_op_offset[insn]];
    for (int j = 0; types[j]; j++) {
      if (types[j] == OPERAND_TYPE_OFFSET || types[j] == OPERAND_TYPE_CDHASH) return false;
    }
    pos += length;
  }
  return true;
}

/* Sets the line of every site that arm_iseq would find in `iseq`. */
static void add_site_lines(const rb_iseq_t *iseq, const VALUE *original, line_bitmap_t *lines) {
  const struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);
  unsigned int entry_count = body->insns_info.size;
  const struct iseq_insn_info_entry *entries = body->insns_info.body;
  if (entry_count == 0 || !entries) return;
  if (body->type == ISEQ_TYPE_TOP || body->type == ISEQ_TYPE_MAIN || body->type == ISEQ_TYPE_EVAL) {
    bool has_events = false;
    for (unsigned int k = 0; k < entry_count && !has_events; k++) has_events = entries[k].events != 0;
    if (!has_events) return;
  }
  for (unsigned int pos = 0; pos < body->iseq_size;) {
    VALUE insn = original[pos];
    unsigned int line = rb_iseq_line_no(iseq, pos);
    if (line > 0) line_bitmap_set(lines, line);
    pos += rb_vm_insn_len_info[insn];
  }
}

/* While walking a fresh compile, an iseq's `initialiser` says whether every iseq holding
 * it ran whole. */
typedef struct {
  pending_iseqs_t *pending;
  bool ran_whole;
} loaded_child_push_t;

static void push_loaded_child(const rb_iseq_t *child, void *data) {
  loaded_child_push_t *push = (loaded_child_push_t *)data;
  if (initialiser_child_p(child, true)) push_pending(push->pending, child, push->ran_whole);
}

static unsigned long count_lines(const line_bitmap_t *lines) {
  unsigned long count = 0;
  for (uint32_t byte = 0; byte < lines->length; byte++) count += (unsigned long)__builtin_popcount(lines->bytes[byte]);
  return count;
}

/* The file's bytes as a UTF-8 string, which is how Ruby reads source; nil if unreadable. */
static VALUE read_source(VALUE path) {
  int fd = open(StringValueCStr(path), O_RDONLY | O_CLOEXEC);
  if (fd < 0) return Qnil;
  struct stat file_stat;
  if (fstat(fd, &file_stat) != 0 || !S_ISREG(file_stat.st_mode) || file_stat.st_size > LONG_MAX) {
    close(fd);
    return Qnil;
  }
  VALUE source = rb_utf8_str_new(NULL, (long)file_stat.st_size);
  char *buffer = RSTRING_PTR(source);
  long length = 0;
  while (length < (long)file_stat.st_size) {
    ssize_t count = read(fd, buffer + length, (size_t)(file_stat.st_size - length));
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    length += count;
  }
  close(fd);
  if (length != (long)file_stat.st_size) return Qnil;
  return source;
}

static VALUE compile_source(VALUE data) {
  VALUE *argv = (VALUE *)data;
  return rb_funcallv(rb_cISeq, id_compile, 5, argv);
}

/* Compiles the source of a file that finished loading, without running it. Compiling the
 * source keeps Ruby's Coverage data of the file, which compile_file resets before Ruby
 * 3.4, and $VERBOSE nil keeps its warnings from showing twice. The copy's absolute path
 * is empty, so that code which looks for the file's iseqs in the heap until the GC frees
 * the copy, such as the static dependency scan, skips it. Returns nil if it cannot be
 * compiled. Exceptions other than StandardError and ScriptError, such as an interrupt,
 * propagate. */
static VALUE compile_loaded_file(VALUE path) {
  VALUE source = read_source(path);
  if (NIL_P(source)) return Qnil;
  VALUE argv[5] = {source, path, rb_str_new(NULL, 0), INT2FIX(1), st.compile_options};
  VALUE errinfo = rb_errinfo();
  VALUE verbose = ruby_verbose;
  ruby_verbose = Qnil;
  int state = 0;
  VALUE compiled = rb_protect(compile_source, (VALUE)argv, &state);
  ruby_verbose = verbose;
  if (state) {
    VALUE error = rb_errinfo();
    if (state != TAG_RAISE ||
        (!rb_obj_is_kind_of(error, rb_eStandardError) && !rb_obj_is_kind_of(error, rb_eScriptError))) {
      st.crediting_loaded_files = false;
      rb_jump_tag(state);
    }
    rb_set_errinfo(errinfo);
    return Qnil;
  }
  return rb_obj_is_kind_of(compiled, rb_cISeq) ? compiled : Qnil;
}

/* A required file is in $LOADED_FEATURES once its top-level iseq has run to its end. An
 * initialiser iseq without branches then ran whole if every iseq holding it did, since
 * initialiser code runs once per load. Lines of the other initialiser iseqs may not have
 * run and are left out. */
static void credit_loaded_file(long file, VALUE path) {
  VALUE compiled = compile_loaded_file(path);
  if (NIL_P(compiled)) {
    st.stats.loaded_file_failures++;
    return;
  }

  line_bitmap_t credited = {0};
  line_bitmap_t left = {0};
  pending_iseqs_t pending = {0};
  /* Raw iseq pointers stay valid only while no GC can move or free them. */
  VALUE gc_was_disabled = rb_gc_disable();
  push_pending(&pending, rb_iseqw_to_iseq(compiled), true);
  while (pending.count > 0) {
    pending_iseq_t next = pending.items[--pending.count];
    const struct rb_iseq_constant_body *body = ISEQ_BODY(next.iseq);
    if (!body || body->iseq_size == 0 || !ISEQ_EXECUTABLE_P(next.iseq)) continue;
    bool had_original = ISEQ_ORIGINAL_ISEQ(next.iseq) != NULL;
    const VALUE *original = rb_iseq_original_iseq(next.iseq);
    bool ran_whole = next.initialiser && runs_whole_p(next.iseq, original);
    add_site_lines(next.iseq, original, ran_whole ? &credited : &left);
    loaded_child_push_t push = {&pending, ran_whole};
    each_child(next.iseq, original, push_loaded_child, &push);
    if (!had_original) ISEQ_ORIGINAL_ISEQ_CLEAR(next.iseq);
  }
  free(pending.items);
  if (gc_was_disabled == Qfalse) rb_gc_enable();
  RB_GC_GUARD(compiled);

  /* A line that a credited iseq shares with another, such as a class line, ran. */
  for (uint32_t byte = 0; byte < left.length && byte < credited.length; byte++) left.bytes[byte] &= ~credited.bytes[byte];
  unsigned long left_count = count_lines(&left);
  st.stats.loaded_lines_credited += count_lines(&credited);
  st.stats.loaded_lines_left += left_count;
  if (left_count) st.stats.loaded_files_with_branches++;
  line_bitmap_or(&st.files[file].init_lines, &credited);
  line_bitmap_or(&st.files[file].initialisers_left, &left);
  free(credited.bytes);
  free(left.bytes);
}

/* Credits the initialisers of the repository files that loaded while the collector did
 * not run. */
static void credit_loaded_files(void) {
  if (insn_leave < 0 || insn_throw < 0) return;
  VALUE features = rb_gv_get("$LOADED_FEATURES");
  if (!RB_TYPE_P(features, T_ARRAY)) return;
  double started_at = now_seconds();
  features = rb_ary_dup(features);
  st.crediting_loaded_files = true;
  for (long i = 0; i < RARRAY_LEN(features); i++) {
    VALUE path = RARRAY_AREF(features, i);
    long file = classify_path(path);
    if (file < 0 || st.files[file].initialisers_known) continue;
    st.files[file].initialisers_known = true;
    st.stats.loaded_files++;
    credit_loaded_file(file, path);
  }
  st.crediting_loaded_files = false;
  st.stats.loaded_files_seconds += now_seconds() - started_at;
  RB_GC_GUARD(features);
}

/* ---- Ractors ---------------------------------------------------------------- */

#if RUBY_API_VERSION_MAJOR < 4
static VALUE gc_state_key;
static VALUE gc_state_none;

static void on_event_flag_sync(VALUE data, const rb_trace_arg_t *trace_arg) {}

/* Before Ruby 4, the GC that frees a Ractor sets the VM's global event flags to that
 * Ractor's hooks: none. The VM checks those flags before it dispatches an instruction
 * event, so no trap fires until a hook of the main Ractor is added or removed, which sets
 * the flags from the main Ractor's hooks again. Ruby exports neither the flags nor whether
 * a Ractor ever ran, so the first context boundary after GC activity adds and removes a
 * hook. With no other Ractor running, the flags keep their value. */
static void sync_event_flags(void) {
  if (rb_gc_count() == st.gc_count_at_flag_sync && !st.gc_running_at_flag_sync) return;
  rb_add_event_hook2((rb_event_hook_func_t)on_event_flag_sync, TRAP_EVENT, Qnil, HOOK_FLAGS);
  rb_remove_event_hook((rb_event_hook_func_t)on_event_flag_sync);
  st.stats.event_flag_syncs++;
  /* A lazy sweep still running can free a Ractor before the next GC starts. */
  st.gc_count_at_flag_sync = rb_gc_count();
  st.gc_running_at_flag_sync = rb_gc_latest_gc_info(gc_state_key) != gc_state_none;
}
#else
/* Ruby 4 checks the hooks of the running Ractor instead. */
static void sync_event_flags(void) {}
#endif

/* ---- contexts --------------------------------------------------------------- */

static void rearm_dirty_sites(void) {
  bool repaired = false;
  for (size_t i = 0; i < st.dirty.count; i++) {
    site_t *site = &st.sites[st.dirty.items[i]];
    site->flags &= ~SITE_DIRTY;
    /* Before arming, which would restore a guard site and hide the damage. */
    if (st.yjit_guarded && repair_guards(&st.records[site->record])) repaired = true;
    arm(site);
  }
  if (repaired) invalidate_yjit_code();
  st.stats.rearms += st.dirty.count;
  st.dirty.count = 0;
}

static void context_clear(context_t *context) {
  for (size_t i = 0; i < context->hit_count; i++) bit_clear(context->bits, context->hits[i].site);
  context->hit_count = 0;
}

static void remove_open(size_t index) {
  for (size_t i = 0; i < st.open_count; i++) {
    if (st.open_contexts[i] == index) {
      st.open_contexts[i] = st.open_contexts[--st.open_count];
      return;
    }
  }
}

static VALUE line_collector_open_context(int argc, VALUE *argv, VALUE self) {
  VALUE fixture;
  rb_scan_args(argc, argv, "01", &fixture);
  if (!st.started) return Qnil;

  size_t index = st.context_count;
  for (size_t i = 0; i < st.context_count; i++) {
    if (st.contexts[i].serial == 0) {
      index = i;
      break;
    }
  }
  if (index == st.context_count) {
    size_t capacity = st.context_capacity;
    if (!grow((void **)&st.contexts, &capacity, st.context_count + 1, sizeof(context_t))) return Qnil;
    st.context_capacity = capacity;
    memset(&st.contexts[index], 0, sizeof(context_t));
    st.context_count++;
  }
  context_t *context = &st.contexts[index];
  if (!context->bits) {
    context->bits = calloc(st.bit_words ? st.bit_words : 1, sizeof(uint64_t));
    if (!context->bits) {
      st.stats.allocation_failures++;
      return Qnil;
    }
  }
  size_t open_capacity = st.open_capacity;
  if (!grow((void **)&st.open_contexts, &open_capacity, st.open_count + 1, sizeof(uint32_t))) return Qnil;
  st.open_capacity = open_capacity;

  context->serial = ++st.next_serial;
  context->open = true;
  context->fixture = RTEST(fixture);
  context->hit_count = 0;
  st.open_contexts[st.open_count++] = (uint32_t)index;
  /* YJIT can be turned on at runtime (RubyVM::YJIT.enable). */
  if (!st.yjit_guarded && yjit_enabled()) enable_yjit_guards();
  sync_event_flags();
  rearm_dirty_sites();
  return LONG2FIX(context->serial);
}

static void close_open_context(context_t *context) {
  context->open = false;
  remove_open((size_t)(context - st.contexts));
  sync_event_flags();
  /* What runs until the next context opens is unowned, and only armed sites record it. */
  if (st.open_count == 0) rearm_dirty_sites();
}

static VALUE line_collector_close_context(VALUE self, VALUE serial) {
  context_t *context = FIXNUM_P(serial) ? context_by_serial(FIX2LONG(serial)) : NULL;
  if (!context || !context->open) return Qfalse;
  close_open_context(context);
  return Qtrue;
}

static void release_context(context_t *context) {
  if (context->open) close_open_context(context);
  if (context->fixture) {
    for (size_t i = 0; i < context->hit_count; i++) {
      const hit_t *hit = &context->hits[i];
      line_bitmap_set(&st.files[hit->file].suite_setup_lines, hit->line);
    }
  }
  context_clear(context);
  context->serial = 0;
}

static void add_context_lines(context_t *context, uint32_t epoch) {
  for (size_t i = 0; i < context->hit_count; i++) {
    const hit_t *hit = &context->hits[i];
    file_t *file = &st.files[hit->file];
    if (file->scratch_epoch != epoch) {
      file->scratch_epoch = epoch;
      if (file->scratch.length) memset(file->scratch.bytes, 0, file->scratch.length);
      id_vector_push(&st.touched, hit->file);
    }
    line_bitmap_set(&file->scratch, hit->line);
  }
}

/* ---- msgpack ---------------------------------------------------------------- */

/* Coverage is packed here as msgpack-ruby packs it from Ruby: a path is a UTF-8 String,
 * which it writes as str, and a bitmap a binary String, which it writes as bin. */

static const uint8_t FILENAME_KEY[] = {0xa8, 'f', 'i', 'l', 'e', 'n', 'a', 'm', 'e'};
static const uint8_t BITMAP_KEY[] = {0xa6, 'b', 'i', 't', 'm', 'a', 'p'};
#define MAP_OF_TWO 0x82

static size_t str_header_size(size_t length) { return length < 32 ? 1 : length < 256 ? 2 : length < 65536 ? 3 : 5; }

static size_t bin_header_size(size_t length) { return length < 256 ? 2 : length < 65536 ? 3 : 5; }

static uint8_t *pack_length(uint8_t *out, uint8_t marker, size_t length, int width) {
  *out++ = marker;
  for (int shift = (width - 1) * 8; shift >= 0; shift -= 8) *out++ = (uint8_t)(length >> shift);
  return out;
}

static uint8_t *pack_str_header(uint8_t *out, size_t length) {
  if (length < 32) {
    *out++ = (uint8_t)(0xa0 | length);
    return out;
  }
  if (length < 256) return pack_length(out, 0xd9, length, 1);
  if (length < 65536) return pack_length(out, 0xda, length, 2);
  return pack_length(out, 0xdb, length, 4);
}

static uint8_t *pack_bin_header(uint8_t *out, size_t length) {
  if (length < 256) return pack_length(out, 0xc4, length, 1);
  if (length < 65536) return pack_length(out, 0xc5, length, 2);
  return pack_length(out, 0xc6, length, 4);
}

static uint8_t *pack_bytes(uint8_t *out, const void *bytes, size_t length) {
  memcpy(out, bytes, length);
  return out + length;
}

static size_t packed_file_size(const file_t *file) {
  size_t path_length = (size_t)RSTRING_LEN(file->path);
  size_t bitmap_length = line_bitmap_used_length(&file->scratch);
  return 1 + sizeof(FILENAME_KEY) + str_header_size(path_length) + path_length + sizeof(BITMAP_KEY) +
         bin_header_size(bitmap_length) + bitmap_length;
}

/* {"filename" => path, "bitmap" => the scratch bitmap} */
static uint8_t *pack_file(uint8_t *out, const file_t *file) {
  size_t path_length = (size_t)RSTRING_LEN(file->path);
  size_t bitmap_length = line_bitmap_used_length(&file->scratch);
  *out++ = MAP_OF_TWO;
  out = pack_bytes(out, FILENAME_KEY, sizeof(FILENAME_KEY));
  out = pack_str_header(out, path_length);
  out = pack_bytes(out, RSTRING_PTR(file->path), path_length);
  out = pack_bytes(out, BITMAP_KEY, sizeof(BITMAP_KEY));
  out = pack_bin_header(out, bitmap_length);
  return pack_bytes(out, file->scratch.bytes, bitmap_length);
}

/* Cov(T) = Own(T) ∪ Fixture(T) ∪ the initialiser lines of every file with a line in
 * either, as [file count, one msgpack map {"filename", "bitmap"} per file, back to back].
 * Packing it here makes one object per test, where a Hash of Strings made one per file
 * and the writer then packed them one by one. Releases the test's context. */
static VALUE line_collector_coverage(VALUE self, VALUE serial, VALUE fixture_serials) {
  context_t *context = FIXNUM_P(serial) ? context_by_serial(FIX2LONG(serial)) : NULL;
  if (!context) return rb_assoc_new(INT2FIX(0), rb_str_new(NULL, 0));

  uint32_t epoch = ++st.epoch;
  st.touched.count = 0;
  add_context_lines(context, epoch);
  if (RB_TYPE_P(fixture_serials, T_ARRAY)) {
    for (long i = 0; i < RARRAY_LEN(fixture_serials); i++) {
      VALUE fixture_serial = RARRAY_AREF(fixture_serials, i);
      context_t *fixture = FIXNUM_P(fixture_serial) ? context_by_serial(FIX2LONG(fixture_serial)) : NULL;
      if (fixture && fixture != context) add_context_lines(fixture, epoch);
    }
  }
  /* Released first: an allocation below that fails raises, and must not leak the context.
   * Releasing reads no scratch bitmap. */
  release_context(context);

  size_t size = 0;
  for (size_t i = 0; i < st.touched.count; i++) {
    file_t *file = &st.files[st.touched.items[i]];
    line_bitmap_or(&file->scratch, &file->init_lines);
    size += packed_file_size(file);
  }
  VALUE packed = rb_str_new(NULL, (long)size);
  uint8_t *out = (uint8_t *)RSTRING_PTR(packed);
  for (size_t i = 0; i < st.touched.count; i++) out = pack_file(out, &st.files[st.touched.items[i]]);
  return rb_assoc_new(SIZET2NUM(st.touched.count), packed);
}

static VALUE line_collector_release(VALUE self, VALUE serial) {
  context_t *context = FIXNUM_P(serial) ? context_by_serial(FIX2LONG(serial)) : NULL;
  if (!context) return Qfalse;
  release_context(context);
  return Qtrue;
}

static VALUE bitmaps_hash(line_bitmap_t *(*select)(file_t *)) {
  VALUE result = rb_hash_new();
  for (size_t i = 0; i < st.file_count; i++) {
    line_bitmap_t *bitmap = select(&st.files[i]);
    uint32_t length = line_bitmap_used_length(bitmap);
    if (length) rb_hash_aset(result, st.files[i].path, rb_str_new((const char *)bitmap->bytes, length));
  }
  return result;
}

static line_bitmap_t *select_init(file_t *file) { return &file->init_lines; }
static line_bitmap_t *select_suite_setup(file_t *file) { return &file->suite_setup_lines; }
static line_bitmap_t *select_scratch(file_t *file) { return &file->scratch; }
static line_bitmap_t *select_initialisers_left(file_t *file) { return &file->initialisers_left; }

/* Shared, in its three parts: init, suiteSetup, unowned. */
static VALUE line_collector_shared(VALUE self) {
  VALUE result = rb_hash_new();
  rb_hash_aset(result, rb_utf8_str_new_cstr("init"), bitmaps_hash(select_init));
  rb_hash_aset(result, rb_utf8_str_new_cstr("suiteSetup"), bitmaps_hash(select_suite_setup));

  uint32_t epoch = ++st.epoch;
  for (size_t i = 0; i < st.file_count; i++) {
    file_t *file = &st.files[i];
    file->scratch_epoch = epoch;
    if (file->scratch.length) memset(file->scratch.bytes, 0, file->scratch.length);
  }
  for (size_t i = 0; i < st.unowned_hits.count; i++) {
    site_t *site = &st.sites[st.unowned_hits.items[i]];
    line_bitmap_set(&site_file(site)->scratch, site->line);
  }
  rb_hash_aset(result, rb_utf8_str_new_cstr("unowned"), bitmaps_hash(select_scratch));
  return result;
}

/* ---- start and stop --------------------------------------------------------- */

/* On a start after a stop: iseqs armed before the stop trap again, except for the
 * initialiser lines already recorded. */
static void rearm_known_sites(void) {
  for (size_t i = 0; i < st.site_count; i++) {
    site_t *site = &st.sites[i];
    if ((site->flags & SITE_INIT) && (site->flags & SITE_INIT_SEEN)) continue;
    arm(site);
  }
}

static VALUE line_collector_start(VALUE self, VALUE root, VALUE ignored_paths) {
  if (st.started) return Qtrue;
  Check_Type(root, T_STRING);
  Check_Type(ignored_paths, T_ARRAY);

  VALUE normalized_root = rb_str_dup(root);
  if (RSTRING_LEN(normalized_root) == 0 || RSTRING_PTR(normalized_root)[RSTRING_LEN(normalized_root) - 1] != '/') {
    rb_str_cat_cstr(normalized_root, "/");
  }
  st.root = rb_obj_freeze(normalized_root);
  st.ignored_paths = rb_obj_freeze(rb_ary_dup(ignored_paths));
  st.path_cache = rb_hash_new();
  st.started = true;

  double started_at = now_seconds();
  /* Enabling an iseq event for the first time makes the VM discard JIT code compiled
   * without trace instructions. */
  rb_add_event_hook2((rb_event_hook_func_t)on_event, TRAP_EVENT, Qnil, HOOK_FLAGS);
  st.trap_hook_installed = true;
  if (!add_compile_event_to_trap_hook()) {
    rb_add_event_hook2((rb_event_hook_func_t)on_script_compiled, RUBY_EVENT_SCRIPT_COMPILED, Qnil, HOOK_FLAGS);
    st.compile_hook_installed = true;
  }

  VALUE gc_was_disabled = rb_gc_disable();
  rearm_known_sites();
  arm_loaded_code();
  /* YJIT guards wait for the first context: until then every site still traps on its
   * first execution, which YJIT cannot compile past. */
  if (gc_was_disabled == Qfalse) rb_gc_enable();
  st.stats.discovery_seconds = now_seconds() - started_at;
  /* After the discovery, which would arm the iseqs it compiles. */
  credit_loaded_files();
  return Qtrue;
}

static VALUE line_collector_stop(VALUE self) {
  if (!st.started) return Qfalse;
  if (st.trap_hook_installed) {
    rb_remove_event_hook((rb_event_hook_func_t)on_event);
    st.trap_hook_installed = false;
  }
  if (st.compile_hook_installed) {
    rb_remove_event_hook((rb_event_hook_func_t)on_script_compiled);
    st.compile_hook_installed = false;
  }
  for (size_t r = 0; r < st.record_count; r++) {
    const iseq_record_t *record = &st.records[r];
    for (uint32_t i = 0; i < record->site_count; i++) {
      site_t *site = &st.sites[record->first_site + i];
      if (site->flags & SITE_ENTRY_FLAGGED) {
        site->entry->events &= ~TRAP_EVENT;
        site->flags &= ~SITE_ENTRY_FLAGGED;
      }
      site->flags &= ~(SITE_ARMED | SITE_DIRTY);
      if (!(site->flags & SITE_SHARED)) untrace_if_unneeded(site, record->iseq);
    }
  }
  st.dirty.count = 0;
  for (size_t i = 0; i < st.open_count; i++) st.contexts[st.open_contexts[i]].open = false;
  st.open_count = 0;
  st.started = false;
  return Qtrue;
}

static VALUE line_collector_stats(VALUE self) {
  VALUE result = rb_hash_new();
#define STAT(name, value) rb_hash_aset(result, ID2SYM(rb_intern(name)), value)
  STAT("sites", ULONG2NUM(st.site_count));
  STAT("iseqs", ULONG2NUM(st.record_count));
  STAT("files", ULONG2NUM(st.file_count));
  STAT("iseqs_skipped", ULONG2NUM(st.stats.iseqs_skipped));
  STAT("spare_branch_counters", ULONG2NUM(st.spare_counter_array_count));
  STAT("yjit_guarded", st.yjit_guarded ? Qtrue : Qfalse);
  STAT("single_hook", st.trap_hook_installed && !st.compile_hook_installed ? Qtrue : Qfalse);
  STAT("guards", ULONG2NUM(st.guard_count));
  STAT("guard_repairs", ULONG2NUM(st.stats.guard_repairs));
  STAT("yjit_invalidations", ULONG2NUM(st.stats.yjit_invalidations));
  STAT("hook_calls", ULONG2NUM(st.stats.hook_calls));
  STAT("foreign_calls", ULONG2NUM(st.stats.foreign_calls));
  STAT("idle_calls", ULONG2NUM(st.stats.idle_calls));
  STAT("entry_aliases", ULONG2NUM(st.stats.entry_aliases));
  STAT("traps", ULONG2NUM(st.stats.traps));
  STAT("init_traps", ULONG2NUM(st.stats.init_traps));
  STAT("unowned_traps", ULONG2NUM(st.stats.unowned_traps));
  STAT("kept_armed", ULONG2NUM(st.stats.kept_armed));
  STAT("disarms", ULONG2NUM(st.stats.disarms));
  STAT("rearms", ULONG2NUM(st.stats.rearms));
  STAT("iseqs_scanned", ULONG2NUM(st.stats.iseqs_scanned));
  STAT("plain_encodings_known", ULONG2NUM(st.plain_known));
  STAT("allocation_failures", ULONG2NUM(st.stats.allocation_failures));
  STAT("event_flag_syncs", ULONG2NUM(st.stats.event_flag_syncs));
  STAT("discovery_seconds", DBL2NUM(st.stats.discovery_seconds));
  STAT("loaded_files", ULONG2NUM(st.stats.loaded_files));
  STAT("loaded_file_failures", ULONG2NUM(st.stats.loaded_file_failures));
  STAT("loaded_files_with_branches", ULONG2NUM(st.stats.loaded_files_with_branches));
  STAT("loaded_lines_credited", ULONG2NUM(st.stats.loaded_lines_credited));
  STAT("loaded_lines_left", ULONG2NUM(st.stats.loaded_lines_left));
  STAT("loaded_lines_left_by_file", bitmaps_hash(select_initialisers_left));
  STAT("loaded_files_seconds", DBL2NUM(st.stats.loaded_files_seconds));
  unsigned long unknown = 0, shared = 0, init = 0;
  for (size_t i = 0; i < st.site_count; i++) {
    if (st.sites[i].flags & SITE_PLAIN_UNKNOWN) unknown++;
    if (st.sites[i].flags & SITE_SHARED) shared++;
    if (st.sites[i].flags & SITE_INIT) init++;
  }
  STAT("plain_unknown_sites", ULONG2NUM(unknown));
  STAT("shared_sites", ULONG2NUM(shared));
  STAT("init_sites", ULONG2NUM(init));
#undef STAT
  return result;
}

static VALUE supported_p(VALUE self) { return Qtrue; }

/* Whether the collector can keep repository code out of YJIT in this Ruby. False also
 * when Ruby is built without YJIT. */
static VALUE yjit_supported_p(VALUE self) {
#if RUBY_API_VERSION_MAJOR == 3 && RUBY_API_VERSION_MINOR < 3
  bool found = yjit_enabled_function != NULL;
#else
  bool found = yjit_enabled_variable != NULL;
#endif
  return found && yjit_invalidate_all ? Qtrue : Qfalse;
}

/* ---- GC ------------------------------------------------------------------- */

static void state_mark(void *unused) {
  rb_gc_mark(st.root);
  rb_gc_mark(st.ignored_paths);
  rb_gc_mark(st.path_cache);
  rb_gc_mark(st.files_by_path);
  rb_gc_mark(st.compile_options);
  for (size_t i = 0; i < st.file_count; i++) rb_gc_mark(st.files[i].path);
  /* Pins every armed iseq: sites point into their instruction buffers. */
  for (size_t i = 0; i < st.record_count; i++) rb_gc_mark((VALUE)st.records[i].iseq);
  for (size_t i = 0; i < st.spare_counter_array_count; i++) rb_gc_mark(st.spare_counter_arrays[i]);
}

static const rb_data_type_t state_type = {
    .wrap_struct_name = "Datadog::CI::TestImpactAnalysis::Coverage::LineCollector state",
    .function = {.dmark = state_mark, .dfree = NULL, .dsize = NULL},
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

void Init_dd_ci_line_coverage(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mTIA = rb_define_module_under(mCI, "TestImpactAnalysis");
  VALUE mCoverage = rb_define_module_under(mTIA, "Coverage");
  VALUE mLineCollector = rb_define_module_under(mCoverage, "LineCollector");

  st.root = Qnil;
  st.ignored_paths = Qnil;
  st.path_cache = Qnil;
  st.context_key = ID2SYM(rb_intern("__datadog_ci_coverage_context"));
  st.spare_counters = st_init_numtable();
#if RUBY_API_VERSION_MAJOR < 4
  gc_state_key = ID2SYM(rb_intern("state"));
  gc_state_none = ID2SYM(rb_intern("none"));
#endif

#if RUBY_API_VERSION_MAJOR == 3 && RUBY_API_VERSION_MINOR < 3
  yjit_enabled_function = (bool (*)(void))dlsym(RTLD_DEFAULT, "rb_yjit_enabled_p");
#else
  yjit_enabled_variable = (const bool *)dlsym(RTLD_DEFAULT, "rb_yjit_enabled_p");
#endif
  yjit_invalidate_all = (void (*)(void))dlsym(RTLD_DEFAULT, "rb_yjit_tracing_invalidate_all");

  state_holder = TypedData_Wrap_Struct(rb_cObject, &state_type, &st);
  rb_gc_register_mark_object(state_holder);

  st.files_by_path = rb_hash_new();
  /* Ruby's Coverage must not see the files the collector compiles. */
  st.compile_options = rb_hash_new();
  rb_hash_aset(st.compile_options, ID2SYM(rb_intern("coverage_enabled")), Qfalse);
  rb_obj_freeze(st.compile_options);
  id_compile = rb_intern("compile");
  ID instruction_names = rb_intern("INSTRUCTION_NAMES");
  VALUE names = rb_const_defined(rb_cRubyVM, instruction_names) ? rb_const_get(rb_cRubyVM, instruction_names) : Qnil;
  for (long i = 0; RB_TYPE_P(names, T_ARRAY) && i < RARRAY_LEN(names); i++) {
    VALUE name = RARRAY_AREF(names, i);
    if (!RB_TYPE_P(name, T_STRING) || RSTRING_LEN(name) != 5) continue;
    if (memcmp(RSTRING_PTR(name), "leave", 5) == 0) insn_leave = i;
    if (memcmp(RSTRING_PTR(name), "throw", 5) == 0) insn_throw = i;
  }

  rb_define_const(mLineCollector, "CONTEXT_KEY", st.context_key);
  rb_define_singleton_method(mLineCollector, "supported?", supported_p, 0);
  rb_define_singleton_method(mLineCollector, "yjit_supported?", yjit_supported_p, 0);
  rb_define_singleton_method(mLineCollector, "start", line_collector_start, 2);
  rb_define_singleton_method(mLineCollector, "stop", line_collector_stop, 0);
  rb_define_singleton_method(mLineCollector, "open_context", line_collector_open_context, -1);
  rb_define_singleton_method(mLineCollector, "close_context", line_collector_close_context, 1);
  rb_define_singleton_method(mLineCollector, "coverage", line_collector_coverage, 2);
  rb_define_singleton_method(mLineCollector, "release", line_collector_release, 1);
  rb_define_singleton_method(mLineCollector, "shared", line_collector_shared, 0);
  rb_define_singleton_method(mLineCollector, "stats", line_collector_stats, 0);
}

#endif
