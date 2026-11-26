#include <ruby.h>

#include "line_coverage.h"

/*
 * Per-test line coverage with one-shot traps.
 *
 * Every instruction that starts a line in repository code (an instruction carrying
 * RUBY_EVENT_LINE) is a site. A site is armed by adding the trap event to its event
 * flags and switching its instruction to the trace variant, so the VM calls one internal
 * hook when it runs. The hook records the line for the context the running fiber
 * carries (a test, a suite fixture, or none), then disarms the site once every open
 * context has recorded it: it clears the trap event and restores the untraced
 * instruction unless the VM still dispatches another event there. Sites disarmed this
 * way are re-armed when the next context opens. Steady-state code runs untraced; the
 * cost is one trap per distinct (context, line).
 *
 * The trap event is one of the two events reserved for Ruby's Coverage, whichever it
 * does not use: RUBY_EVENT_COVERAGE_BRANCH, or RUBY_EVENT_COVERAGE_LINE once code
 * compiled under branch coverage shows up. With line and branch coverage both on, sites
 * whose flags already carry RUBY_EVENT_COVERAGE_LINE are shared: Ruby keeps them traced,
 * so the hook runs on every execution and returns early unless the site is armed.
 *
 * Initialiser code (a file's top level and class or module bodies) records into the
 * file's initialiser lines once per process and is never re-armed.
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

#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* Generated into insns_info.inc, which the private headers do not ship; exported by
 * libruby for debuggers. */
extern const uint8_t rb_vm_insn_len_info[];
extern const char rb_vm_insn_op_base[];
extern const unsigned short rb_vm_insn_op_offset[];

#define OPERAND_TYPE_ISEQ 'S'

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
};

typedef struct {
  VALUE *slot;  /* the instruction in iseq_encoded */
  VALUE plain;  /* encoding to restore on disarm */
  VALUE trace;  /* encoding that traps */
  struct iseq_insn_info_entry *entry;
  uint32_t pos;
  uint32_t file;
  uint32_t line;
  uint16_t insn;
  uint8_t flags;
} site_t;

/* Above any instruction number the VM defines; insns.inc is not shipped. */
#define INSN_TABLE_SIZE 512

typedef struct {
  const rb_iseq_t *iseq;
  uint32_t first_site;
  uint32_t site_count;
} iseq_record_t;

typedef struct {
  uint8_t *bytes;
  uint32_t length;
} line_bitmap_t;

typedef struct {
  VALUE path; /* repository-relative */
  line_bitmap_t init_lines;
  line_bitmap_t suite_setup_lines;
  line_bitmap_t scratch;
  uint32_t scratch_epoch;
} file_t;

typedef struct {
  long serial; /* 0: free slot */
  bool open;
  bool fixture;
  uint64_t *bits; /* one bit per site */
  uint32_t *hits; /* sites recorded, in order */
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
  bool line_hook_installed;
  bool branch_hook_installed;
  rb_event_flag_t trap_event;
  VALUE root;          /* realpath of the repository root, with a trailing '/' */
  VALUE ignored_paths; /* realpath prefixes excluded on top of the dependency directories */
  VALUE path_cache;    /* iseq path -> file index (Integer) or false */
  VALUE context_key;   /* fiber storage key */

  site_t *sites;
  size_t site_count;
  size_t site_capacity;

  iseq_record_t *records;
  size_t record_count;
  size_t record_capacity;

  /* open addressing, iseq pointer -> record index + 1 */
  uintptr_t *map_keys;
  uint32_t *map_values;
  size_t map_capacity;
  size_t map_count;
  /* the last lookup; consecutive traps usually come from one iseq */
  const rb_iseq_t *cached_iseq;
  long cached_record;

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
  uint32_t epoch;

  /* untraced encoding by instruction number, learned while arming; 0 while unknown */
  VALUE plain_by_insn[INSN_TABLE_SIZE];
  size_t plain_known;

  struct {
    unsigned long hook_calls;
    unsigned long foreign_calls;
    unsigned long idle_calls;
    unsigned long trap_event_switches;
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
    double discovery_seconds;
  } stats;
} st;

static VALUE state_holder = Qnil;

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

static bool line_bitmap_set(line_bitmap_t *bitmap, uint32_t line) {
  uint32_t byte = line >> 3;
  if (byte >= bitmap->length) {
    uint32_t new_length = bitmap->length ? bitmap->length : 16;
    while (new_length <= byte) new_length *= 2;
    uint8_t *grown = realloc(bitmap->bytes, new_length);
    if (!grown) {
      st.stats.allocation_failures++;
      return false;
    }
    memset(grown + bitmap->length, 0, new_length - bitmap->length);
    bitmap->bytes = grown;
    bitmap->length = new_length;
  }
  /* Java order: bit (line & 7) of byte (line >> 3). */
  bitmap->bytes[byte] |= (uint8_t)(1 << (line & 7));
  return true;
}

static void line_bitmap_or(line_bitmap_t *target, const line_bitmap_t *source) {
  for (uint32_t byte = 0; byte < source->length; byte++) {
    uint8_t value = source->bytes[byte];
    if (!value) continue;
    for (int bit = 0; bit < 8; bit++) {
      if (value & (1 << bit)) line_bitmap_set(target, byte * 8 + bit);
    }
  }
}

static uint32_t line_bitmap_used_length(const line_bitmap_t *bitmap) {
  uint32_t length = bitmap->length;
  while (length > 0 && bitmap->bytes[length - 1] == 0) length--;
  return length;
}

/* ---- iseq map ------------------------------------------------------------ */

static inline size_t map_slot(uintptr_t key, size_t capacity) {
  return (size_t)(((uint64_t)(key >> 4) * 11400714819323198485ull) >> 20) & (capacity - 1);
}

static long map_get(const rb_iseq_t *iseq) {
  if (!st.map_capacity) return -1;
  uintptr_t key = (uintptr_t)iseq;
  size_t index = map_slot(key, st.map_capacity);
  for (;;) {
    uintptr_t current = st.map_keys[index];
    if (current == key) return (long)st.map_values[index] - 1;
    if (current == 0) return -1;
    index = (index + 1) & (st.map_capacity - 1);
  }
}

static void map_insert_unchecked(uintptr_t key, uint32_t value) {
  size_t index = map_slot(key, st.map_capacity);
  while (st.map_keys[index] != 0 && st.map_keys[index] != key) index = (index + 1) & (st.map_capacity - 1);
  if (st.map_keys[index] == 0) st.map_count++;
  st.map_keys[index] = key;
  st.map_values[index] = value;
}

static bool map_put(const rb_iseq_t *iseq, uint32_t record) {
  if ((st.map_count + 1) * 2 > st.map_capacity) {
    size_t old_capacity = st.map_capacity;
    uintptr_t *old_keys = st.map_keys;
    uint32_t *old_values = st.map_values;
    size_t new_capacity = old_capacity ? old_capacity * 2 : 4096;
    uintptr_t *keys = calloc(new_capacity, sizeof(uintptr_t));
    uint32_t *values = calloc(new_capacity, sizeof(uint32_t));
    if (!keys || !values) {
      free(keys);
      free(values);
      st.stats.allocation_failures++;
      return false;
    }
    st.map_keys = keys;
    st.map_values = values;
    st.map_capacity = new_capacity;
    st.map_count = 0;
    for (size_t i = 0; i < old_capacity; i++) {
      if (old_keys[i]) map_insert_unchecked(old_keys[i], old_values[i]);
    }
    free(old_keys);
    free(old_values);
  }
  map_insert_unchecked((uintptr_t)iseq, record + 1);
  /* The cache may hold this address as unknown: a freed iseq's slot can be reused. */
  st.cached_iseq = NULL;
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

  size_t file_capacity = st.file_capacity;
  if (!grow((void **)&st.files, &file_capacity, st.file_count + 1, sizeof(file_t))) goto done;
  st.file_capacity = file_capacity;
  file_t *file = &st.files[st.file_count];
  memset(file, 0, sizeof(*file));
  file->path = rb_obj_freeze(rb_str_new_cstr(relative));
  result = (long)st.file_count++;

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

/* `<top (required)>`, `<main>`, `<class:...>`, `<module:...>`, `singleton class`: the
 * frame labels the accuracy reference treats as initialiser code. */
static bool initialiser_label_p(VALUE label) {
  if (!RB_TYPE_P(label, T_STRING)) return false;
  const char *text = RSTRING_PTR(label);
  long length = RSTRING_LEN(label);
  if ((length == 16 && memcmp(text, "<top (required)>", 16) == 0) || (length == 6 && memcmp(text, "<main>", 6) == 0) ||
      (length == 15 && memcmp(text, "singleton class", 15) == 0)) {
    return true;
  }
  const char *rest = NULL;
  if (length >= 8 && memcmp(text, "<class:", 7) == 0) rest = text + 7;
  if (length >= 9 && memcmp(text, "<module:", 8) == 0) rest = text + 8;
  if (!rest || text[length - 1] != '>') return false;
  return memchr(rest, '>', (size_t)(text + length - 1 - rest)) == NULL;
}

/* ---- the trap event --------------------------------------------------------- */

static void on_trap_line(VALUE data, const rb_trace_arg_t *trace_arg);
static void on_trap_branch(VALUE data, const rb_trace_arg_t *trace_arg);

static void install_trap_hook(rb_event_flag_t event) {
  /* Enabling an iseq event for the first time makes the VM discard JIT code compiled
   * without trace instructions. */
  rb_event_hook_flag_t flags = RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG;
  if (event == RUBY_EVENT_COVERAGE_LINE && !st.line_hook_installed) {
    rb_add_event_hook2((rb_event_hook_func_t)on_trap_line, RUBY_EVENT_COVERAGE_LINE, Qnil, flags);
    st.line_hook_installed = true;
  } else if (event == RUBY_EVENT_COVERAGE_BRANCH && !st.branch_hook_installed) {
    rb_add_event_hook2((rb_event_hook_func_t)on_trap_branch, RUBY_EVENT_COVERAGE_BRANCH, Qnil, flags);
    st.branch_hook_installed = true;
  }
}

static void remove_trap_hook(rb_event_flag_t event) {
  if (event == RUBY_EVENT_COVERAGE_LINE && st.line_hook_installed) {
    rb_remove_event_hook((rb_event_hook_func_t)on_trap_line);
    st.line_hook_installed = false;
  } else if (event == RUBY_EVENT_COVERAGE_BRANCH && st.branch_hook_installed) {
    rb_remove_event_hook((rb_event_hook_func_t)on_trap_branch);
    st.branch_hook_installed = false;
  }
}

/* Whether the iseq was compiled under Ruby's branch coverage. Its branch hook then reads
 * a counter index for every instruction that carries RUBY_EVENT_COVERAGE_BRANCH, so that
 * event must stay off every other instruction. */
static bool branch_coverage_p(const rb_iseq_t *iseq) {
  VALUE coverage = ISEQ_COVERAGE(iseq);
  return RB_TYPE_P(coverage, T_ARRAY) && RARRAY_LEN(coverage) > COVERAGE_INDEX_BRANCHES &&
         RTEST(RARRAY_AREF(coverage, COVERAGE_INDEX_BRANCHES));
}

/* Moves every trap to RUBY_EVENT_COVERAGE_LINE. Sites whose entry already carries it,
 * from Ruby's line coverage, become shared. */
static void switch_trap_event_to_line(void) {
  if (st.trap_event == RUBY_EVENT_COVERAGE_LINE) return;
  install_trap_hook(RUBY_EVENT_COVERAGE_LINE);
  for (size_t i = 0; i < st.site_count; i++) {
    site_t *site = &st.sites[i];
    if (site->flags & SITE_ENTRY_FLAGGED) {
      site->entry->events &= ~st.trap_event;
      site->flags &= ~SITE_ENTRY_FLAGGED;
    }
  }
  for (size_t i = 0; i < st.site_count; i++) {
    site_t *site = &st.sites[i];
    site->flags &= ~SITE_SHARED;
    if (site->entry->events & RUBY_EVENT_COVERAGE_LINE) site->flags |= SITE_SHARED;
  }
  for (size_t i = 0; i < st.site_count; i++) {
    site_t *site = &st.sites[i];
    if ((site->flags & SITE_ARMED) && !(site->flags & SITE_SHARED)) {
      site->entry->events |= RUBY_EVENT_COVERAGE_LINE;
      site->flags |= SITE_ENTRY_FLAGGED;
    }
  }
  remove_trap_hook(st.trap_event);
  st.trap_event = RUBY_EVENT_COVERAGE_LINE;
  st.stats.trap_event_switches++;
}

/* ---- arming --------------------------------------------------------------- */

static bool add_site(uint32_t pos, struct iseq_insn_info_entry *entry, uint32_t file, uint32_t line, uint8_t flags) {
  size_t capacity = st.site_capacity;
  if (!grow((void **)&st.sites, &capacity, st.site_count + 1, sizeof(site_t))) return false;
  st.site_capacity = capacity;
  site_t *site = &st.sites[st.site_count++];
  memset(site, 0, sizeof(*site));
  site->pos = pos;
  site->entry = entry;
  site->file = file;
  site->line = line;
  site->flags = flags;
  return true;
}

/* Finds the line-start instructions of `iseq`, registers them as sites, and arms them.
 * Pushes the child iseqs onto `children` when given. */
static void arm_iseq(const rb_iseq_t *iseq, long file, const rb_iseq_t ***children, size_t *child_count,
                     size_t *child_capacity) {
  struct rb_iseq_constant_body *body = (struct rb_iseq_constant_body *)ISEQ_BODY(iseq);
  st.stats.iseqs_scanned++;
  if (!body || body->iseq_size == 0 || !ISEQ_EXECUTABLE_P(iseq)) return;

  bool had_original = ISEQ_ORIGINAL_ISEQ(iseq) != NULL;
  VALUE *original = rb_iseq_original_iseq(iseq);

  if (children) {
    if (body->catch_table) {
      for (unsigned int i = 0; i < body->catch_table->size; i++) {
        const struct iseq_catch_table_entry *entry = UNALIGNED_MEMBER_PTR(body->catch_table, entries[i]);
        if (entry->iseq && grow((void **)children, child_capacity, *child_count + 1, sizeof(rb_iseq_t *))) {
          (*children)[(*child_count)++] = entry->iseq;
        }
      }
    }
    for (unsigned int pos = 0; pos < body->iseq_size;) {
      VALUE insn = original[pos];
      const char *types = &rb_vm_insn_op_base[rb_vm_insn_op_offset[insn]];
      for (int j = 0; types[j]; j++) {
        if (types[j] == OPERAND_TYPE_ISEQ) {
          const rb_iseq_t *child = (const rb_iseq_t *)original[pos + j + 1];
          if (child && grow((void **)children, child_capacity, *child_count + 1, sizeof(rb_iseq_t *))) {
            (*children)[(*child_count)++] = child;
          }
        }
      }
      pos += rb_vm_insn_len_info[insn];
    }
  }

  if (file < 0 || map_get(iseq) >= 0) goto done;

  unsigned int entry_count = body->insns_info.size;
  struct iseq_insn_info_entry *entries = (struct iseq_insn_info_entry *)body->insns_info.body;
  if (entry_count == 0 || !entries) goto done;

  if (branch_coverage_p(iseq)) switch_trap_event_to_line();
  uint8_t base_flags = SITE_ARMED | (initialiser_label_p(rb_iseq_label(iseq)) ? SITE_INIT : 0);

  /* rb_iseq_line_no(iseq, pos) returns the line of the entry covering pos; numbering
   * the entries first turns it into the entry lookup, whatever the table encoding. No
   * Ruby code runs while the numbers are swapped. */
  int *lines = malloc(entry_count * sizeof(int));
  if (!lines) {
    st.stats.allocation_failures++;
    goto done;
  }
  for (unsigned int k = 0; k < entry_count; k++) {
    lines[k] = entries[k].line_no;
    entries[k].line_no = (int)k + 1;
  }

  VALUE *encoded = (VALUE *)body->iseq_encoded;
  size_t first = st.site_count;
  for (unsigned int pos = 0; pos < body->iseq_size;) {
    VALUE insn = original[pos];
    unsigned int k = rb_iseq_line_no(iseq, pos);
    if (k >= 1 && k <= entry_count) {
      if (entries[k - 1].events == 0) plain_learn(insn, encoded[pos]);
      if ((entries[k - 1].events & RUBY_EVENT_LINE) && lines[k - 1] > 0 && insn < INSN_TABLE_SIZE) {
        if (!add_site(pos, &entries[k - 1], (uint32_t)file, (uint32_t)lines[k - 1], base_flags)) break;
        st.sites[st.site_count - 1].insn = (uint16_t)insn;
      }
    }
    pos += rb_vm_insn_len_info[insn];
  }
  for (unsigned int k = 0; k < entry_count; k++) entries[k].line_no = lines[k];
  free(lines);

  size_t count = st.site_count - first;
  if (count == 0 || !ensure_bit_capacity(st.site_count)) {
    st.site_count = first;
    goto done;
  }

  size_t record_capacity = st.record_capacity;
  if (!grow((void **)&st.records, &record_capacity, st.record_count + 1, sizeof(iseq_record_t))) {
    st.site_count = first;
    goto done;
  }
  st.record_capacity = record_capacity;

  for (size_t i = first; i < st.site_count; i++) {
    site_t *site = &st.sites[i];
    site->slot = &encoded[site->pos];
    site->plain = *site->slot;
    if (i > first && st.sites[i - 1].entry == site->entry) st.stats.entry_aliases++;
    if (site->entry->events & st.trap_event) site->flags |= SITE_SHARED;
  }
  for (size_t i = first; i < st.site_count; i++) {
    site_t *site = &st.sites[i];
    if (site->flags & SITE_SHARED) continue;
    site->entry->events |= st.trap_event;
    site->flags |= SITE_ENTRY_FLAGGED;
  }

  /* Let the VM switch the flagged instructions to their trace variants. It keeps every
   * instruction that is already traced. */
  rb_iseq_t *mutable_iseq = (rb_iseq_t *)iseq;
  rb_event_flag_t global_events = mutable_iseq->aux.exec.global_trace_events;
  mutable_iseq->aux.exec.global_trace_events = 0;
  rb_iseq_trace_set(iseq, global_events | st.trap_event);

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
  record->iseq = iseq;
  record->first_site = (uint32_t)first;
  record->site_count = (uint32_t)count;
  if (!map_put(iseq, (uint32_t)st.record_count)) {
    /* Leave the sites armed but unknown to the hook; it ignores them. */
    goto done;
  }
  st.record_count++;
  st.stats.iseqs_armed++;

done:
  if (!had_original) ISEQ_ORIGINAL_ISEQ_CLEAR(iseq);
}

/* Arms an iseq and everything nested in it. */
static void arm_tree(const rb_iseq_t *top) {
  const rb_iseq_t **stack = NULL;
  size_t count = 0, capacity = 0;
  if (!grow((void **)&stack, &capacity, 1, sizeof(rb_iseq_t *))) return;
  stack[count++] = top;
  while (count > 0) {
    const rb_iseq_t *iseq = stack[--count];
    if (map_get(iseq) >= 0) continue;
    long file = classify_path(rb_iseq_path(iseq));
    if (file < 0) continue; /* nested code shares its parent's file */
    arm_iseq(iseq, file, &stack, &count, &capacity);
  }
  free(stack);
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

/* Restores the untraced instruction unless the VM may still dispatch an event there. The
 * test is Ruby's own when it clears an event flag: once an event has been enabled, Ruby
 * relies on the instructions that carry it staying traced. */
static void untrace_if_unneeded(site_t *site, const rb_iseq_t *iseq) {
  if (*site->slot != site->trace) return;
  rb_event_flag_t needed = iseq->aux.exec.global_trace_events;
  if (iseq->aux.exec.local_hooks) needed |= iseq->aux.exec.local_hooks->events;
  if (site->entry->events & needed) return;
  if (site->flags & SITE_PLAIN_UNKNOWN) {
    if (!plain_for(site, &site->plain)) return;
    site->flags &= ~SITE_PLAIN_UNKNOWN;
  }
  *site->slot = site->plain;
}

/* Returns whether the site was armed. A shared site stays traced for Ruby's Coverage;
 * the hook ignores it until it is armed again. */
static bool disarm(site_t *site, const rb_iseq_t *iseq) {
  if (!(site->flags & SITE_ARMED)) return false;
  site->flags &= ~SITE_ARMED;
  st.stats.disarms++;
  if (site->flags & SITE_SHARED) return true;
  if (site->flags & SITE_ENTRY_FLAGGED) {
    site->entry->events &= ~st.trap_event;
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
    site->entry->events |= st.trap_event;
    site->flags |= SITE_ENTRY_FLAGGED;
  }
  *site->slot = site->trace;
}

static long find_site(const iseq_record_t *record, uint32_t pos) {
  long low = record->first_site, high = (long)record->first_site + record->site_count - 1;
  while (low <= high) {
    long middle = (low + high) >> 1;
    uint32_t current = st.sites[middle].pos;
    if (current == pos) return middle;
    if (current < pos) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return -1;
}

static void on_trap(const rb_trace_arg_t *trace_arg) {
  st.stats.hook_calls++;
  const rb_control_frame_t *cfp = trace_arg->cfp;
  const rb_iseq_t *iseq = cfp->iseq;
  long record_index;
  if (iseq == st.cached_iseq) {
    record_index = st.cached_record;
  } else {
    record_index = map_get(iseq);
    st.cached_iseq = iseq;
    st.cached_record = record_index;
  }
  if (record_index < 0) {
    st.stats.foreign_calls++;
    return;
  }
  const iseq_record_t *record = &st.records[record_index];
  /* The VM advanced pc past the instruction before calling hooks. */
  long pos = (long)(cfp->pc - ISEQ_BODY(iseq)->iseq_encoded) - 1;
  long site_index = find_site(record, (uint32_t)pos);
  if (site_index < 0) {
    st.stats.foreign_calls++;
    return;
  }
  site_t *site = &st.sites[site_index];
  if (!(site->flags & SITE_ARMED)) {
    st.stats.idle_calls++;
    return;
  }
  st.stats.traps++;

  if (site->flags & SITE_INIT) {
    st.stats.init_traps++;
    if (!(site->flags & SITE_INIT_SEEN)) {
      site->flags |= SITE_INIT_SEEN;
      line_bitmap_set(&st.files[site->file].init_lines, site->line);
    }
    disarm(site, iseq);
    return;
  }

  uint32_t id = (uint32_t)site_index;
  context_t *context = context_for(trace_arg->ec);
  if (context) {
    if (!bit_test_and_set(context->bits, id)) {
      if (!grow((void **)&context->hits, &context->hit_capacity, context->hit_count + 1, sizeof(uint32_t))) return;
      context->hits[context->hit_count++] = id;
    }
  } else {
    st.stats.unowned_traps++;
    if (!bit_test_and_set(st.unowned_bits, id)) id_vector_push(&st.unowned_hits, id);
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

static void on_trap_line(VALUE data, const rb_trace_arg_t *trace_arg) { on_trap(trace_arg); }

static void on_trap_branch(VALUE data, const rb_trace_arg_t *trace_arg) { on_trap(trace_arg); }

static void on_script_compiled(VALUE data, const rb_trace_arg_t *trace_arg) {
  VALUE compiled = trace_arg->data;
  if (RB_TYPE_P(compiled, T_ARRAY)) compiled = RARRAY_AREF(compiled, 1);
  if (!RB_TYPE_P(compiled, T_IMEMO) || imemo_type(compiled) != imemo_iseq) return;
  VALUE gc_was_disabled = rb_gc_disable();
  arm_tree((const rb_iseq_t *)compiled);
  if (gc_was_disabled == Qfalse) rb_gc_enable();
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

static void arm_loaded_code(void) {
  iseq_list_t list = {0};
  rb_objspace_each_objects(collect_iseqs, &list);
  for (size_t i = 0; i < list.count; i++) {
    const rb_iseq_t *iseq = list.items[i];
    if (map_get(iseq) >= 0) continue;
    long file = classify_path(rb_iseq_path(iseq));
    if (file >= 0) arm_iseq(iseq, file, NULL, NULL, NULL);
  }
  free(list.items);
}

/* ---- contexts --------------------------------------------------------------- */

static void rearm_dirty_sites(void) {
  for (size_t i = 0; i < st.dirty.count; i++) {
    site_t *site = &st.sites[st.dirty.items[i]];
    site->flags &= ~SITE_DIRTY;
    arm(site);
  }
  st.stats.rearms += st.dirty.count;
  st.dirty.count = 0;
}

static void context_clear(context_t *context) {
  for (size_t i = 0; i < context->hit_count; i++) {
    uint32_t id = context->hits[i];
    context->bits[id >> 6] &= ~((uint64_t)1 << (id & 63));
  }
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
  rearm_dirty_sites();
  return LONG2FIX(context->serial);
}

static VALUE line_collector_close_context(VALUE self, VALUE serial) {
  context_t *context = FIXNUM_P(serial) ? context_by_serial(FIX2LONG(serial)) : NULL;
  if (!context || !context->open) return Qfalse;
  context->open = false;
  remove_open((size_t)(context - st.contexts));
  return Qtrue;
}

static void release_context(context_t *context) {
  if (context->open) {
    context->open = false;
    remove_open((size_t)(context - st.contexts));
  }
  if (context->fixture) {
    for (size_t i = 0; i < context->hit_count; i++) {
      site_t *site = &st.sites[context->hits[i]];
      line_bitmap_set(&st.files[site->file].suite_setup_lines, site->line);
    }
  }
  context_clear(context);
  context->serial = 0;
}

static void add_context_lines(context_t *context, uint32_t epoch, id_vector_t *touched) {
  for (size_t i = 0; i < context->hit_count; i++) {
    site_t *site = &st.sites[context->hits[i]];
    file_t *file = &st.files[site->file];
    if (file->scratch_epoch != epoch) {
      file->scratch_epoch = epoch;
      if (file->scratch.length) memset(file->scratch.bytes, 0, file->scratch.length);
      id_vector_push(touched, site->file);
    }
    line_bitmap_set(&file->scratch, site->line);
  }
}

/* Cov(T) = Own(T) ∪ Fixture(T) ∪ the initialiser lines of every file with a line in
 * either. Releases the test's context. */
static VALUE line_collector_coverage(VALUE self, VALUE serial, VALUE fixture_serials) {
  VALUE result = rb_hash_new();
  context_t *context = FIXNUM_P(serial) ? context_by_serial(FIX2LONG(serial)) : NULL;
  if (!context) return result;

  uint32_t epoch = ++st.epoch;
  id_vector_t touched = {0};
  add_context_lines(context, epoch, &touched);
  if (RB_TYPE_P(fixture_serials, T_ARRAY)) {
    for (long i = 0; i < RARRAY_LEN(fixture_serials); i++) {
      VALUE fixture_serial = RARRAY_AREF(fixture_serials, i);
      context_t *fixture = FIXNUM_P(fixture_serial) ? context_by_serial(FIX2LONG(fixture_serial)) : NULL;
      if (fixture && fixture != context) add_context_lines(fixture, epoch, &touched);
    }
  }
  for (size_t i = 0; i < touched.count; i++) {
    file_t *file = &st.files[touched.items[i]];
    line_bitmap_or(&file->scratch, &file->init_lines);
    rb_hash_aset(result, file->path, rb_str_new((const char *)file->scratch.bytes, line_bitmap_used_length(&file->scratch)));
  }
  free(touched.items);
  release_context(context);
  return result;
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

/* Shared, in its three parts: init, suiteSetup, unowned. */
static VALUE line_collector_shared(VALUE self) {
  VALUE result = rb_hash_new();
  rb_hash_aset(result, rb_str_new_cstr("init"), bitmaps_hash(select_init));
  rb_hash_aset(result, rb_str_new_cstr("suiteSetup"), bitmaps_hash(select_suite_setup));

  uint32_t epoch = ++st.epoch;
  for (size_t i = 0; i < st.file_count; i++) {
    file_t *file = &st.files[i];
    file->scratch_epoch = epoch;
    if (file->scratch.length) memset(file->scratch.bytes, 0, file->scratch.length);
  }
  for (size_t i = 0; i < st.unowned_hits.count; i++) {
    site_t *site = &st.sites[st.unowned_hits.items[i]];
    line_bitmap_set(&st.files[site->file].scratch, site->line);
  }
  rb_hash_aset(result, rb_str_new_cstr("unowned"), bitmaps_hash(select_scratch));
  return result;
}

/* ---- start and stop --------------------------------------------------------- */

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
  st.trap_event = RUBY_EVENT_COVERAGE_BRANCH;
  install_trap_hook(st.trap_event);
  rb_add_event_hook2((rb_event_hook_func_t)on_script_compiled, RUBY_EVENT_SCRIPT_COMPILED, Qnil,
                     RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG);
  st.compile_hook_installed = true;

  VALUE gc_was_disabled = rb_gc_disable();
  arm_loaded_code();
  if (gc_was_disabled == Qfalse) rb_gc_enable();
  st.stats.discovery_seconds = now_seconds() - started_at;
  return Qtrue;
}

static VALUE line_collector_stop(VALUE self) {
  if (!st.started) return Qfalse;
  remove_trap_hook(RUBY_EVENT_COVERAGE_LINE);
  remove_trap_hook(RUBY_EVENT_COVERAGE_BRANCH);
  if (st.compile_hook_installed) {
    rb_remove_event_hook((rb_event_hook_func_t)on_script_compiled);
    st.compile_hook_installed = false;
  }
  for (size_t r = 0; r < st.record_count; r++) {
    const iseq_record_t *record = &st.records[r];
    for (uint32_t i = 0; i < record->site_count; i++) {
      site_t *site = &st.sites[record->first_site + i];
      if (site->flags & SITE_ENTRY_FLAGGED) {
        site->entry->events &= ~st.trap_event;
        site->flags &= ~SITE_ENTRY_FLAGGED;
      }
      site->flags &= ~SITE_ARMED;
      if (!(site->flags & SITE_SHARED)) untrace_if_unneeded(site, record->iseq);
    }
  }
  st.dirty.count = 0;
  st.started = false;
  return Qtrue;
}

static VALUE line_collector_stats(VALUE self) {
  VALUE result = rb_hash_new();
#define STAT(name, value) rb_hash_aset(result, ID2SYM(rb_intern(name)), value)
  STAT("sites", ULONG2NUM(st.site_count));
  STAT("iseqs", ULONG2NUM(st.record_count));
  STAT("files", ULONG2NUM(st.file_count));
  STAT("trap_event", rb_str_new_cstr(st.trap_event == RUBY_EVENT_COVERAGE_LINE ? "coverage_line" : "coverage_branch"));
  STAT("trap_event_switches", ULONG2NUM(st.stats.trap_event_switches));
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
  STAT("discovery_seconds", DBL2NUM(st.stats.discovery_seconds));
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

/* ---- GC ------------------------------------------------------------------- */

static void state_mark(void *unused) {
  rb_gc_mark(st.root);
  rb_gc_mark(st.ignored_paths);
  rb_gc_mark(st.path_cache);
  for (size_t i = 0; i < st.file_count; i++) rb_gc_mark(st.files[i].path);
  /* Pins every armed iseq: sites point into their instruction buffers. */
  for (size_t i = 0; i < st.record_count; i++) rb_gc_mark((VALUE)st.records[i].iseq);
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

  state_holder = TypedData_Wrap_Struct(rb_cObject, &state_type, &st);
  rb_gc_register_mark_object(state_holder);

  rb_define_const(mLineCollector, "CONTEXT_KEY", st.context_key);
  rb_define_singleton_method(mLineCollector, "supported?", supported_p, 0);
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
