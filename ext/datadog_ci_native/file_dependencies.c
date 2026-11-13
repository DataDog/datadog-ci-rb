#include "file_dependencies.h"
#include "datadog_common.h"
#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/io.h"
#include "ruby/thread.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/attr.h>
#endif

struct dependency_paths {
  VALUE path, root, ignored;
  char *absolute, *directory, *resolved;
  bool relative, ready;
};

// Darwin's getcwd/realpath walk ancestors. FULLPATH resolves through the
// kernel in one call. UNIQUE rejects hard links, for which FULLPATH can return
// a different name; unsupported flags/filesystems fall back to POSIX realpath.
static char *full_path(const char *path) {
#if defined(__APPLE__) && defined(FSOPT_UNIQUE)
  struct attrlist attributes = {0};
  attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
  attributes.commonattr = ATTR_CMN_FULLPATH;
  struct {
    uint32_t size;
    attrreference_t reference;
    char buffer[PATH_MAX];
  } result;
  if (getattrlist(path, &attributes, &result, sizeof(result), FSOPT_UNIQUE) == 0) {
    size_t offset = result.reference.attr_dataoffset;
    size_t length = result.reference.attr_length;
    if (offset >= sizeof(result.reference) && length > 0 &&
        offset <= sizeof(result) - sizeof(result.size) &&
        length <= sizeof(result) - sizeof(result.size) - offset) {
      const char *value = (char *)&result.reference + offset;
      if (value[length - 1] == '\0') return strdup(value);
    }
  }
#endif
  return NULL;
}

// Only copied C strings are accessed without the GVL. No path results are
// cached: chdir, directory renames and symlink retargets take effect immediately.
static void *resolve_paths(void *pointer) {
  struct dependency_paths *paths = pointer;
  if (paths->relative) {
    paths->directory = full_path(".");
    if (!paths->directory) paths->directory = getcwd(NULL, 0);
    if (!paths->directory) return NULL;
    size_t size = strlen(paths->directory) + strlen(paths->absolute) + 2;
    char *absolute = malloc(size);
    if (!absolute) return NULL;
    snprintf(absolute, size, "%s/%s", paths->directory, paths->absolute);
    free(paths->absolute);
    paths->absolute = absolute;
  }
  // Preserve .. until after symlinks have been followed.
  paths->resolved = full_path(paths->absolute);
  if (!paths->resolved) paths->resolved = realpath(paths->absolute, NULL);
  paths->ready = true;
  return NULL;
}

static bool ascii_path(const char *path) {
  if (!path) return true;
  for (const unsigned char *p = (const unsigned char *)path; *p; p++) {
    if (*p >= 128) return false;
  }
  return true;
}

// Avoid allocating a base string and invoking Ruby's path normalizer when
// the absolute spelling is already normalized. All other shapes use Ruby.
static bool normalized_path(const char *path) {
  const char *segment = path + 1;
  for (const char *p = segment;; p++) {
    if (*p != '/' && *p != '\0') continue;
    size_t length = p - segment;
    if (length == 0 || (length == 1 && segment[0] == '.') ||
        (length == 2 && segment[0] == '.' && segment[1] == '.')) return false;
    if (*p == '\0') return true;
    segment = p + 1;
  }
}

static bool included(const char *path, struct dependency_paths *paths) {
  return dd_ci_is_path_included(path, strlen(path),
    RSTRING_PTR(paths->root), RSTRING_LEN(paths->root),
    NIL_P(paths->ignored) ? NULL : RSTRING_PTR(paths->ignored),
    NIL_P(paths->ignored) ? 0 : RSTRING_LEN(paths->ignored));
}

static VALUE collect_paths(VALUE data) {
  struct dependency_paths *paths = (struct dependency_paths *)data;
  rb_thread_call_without_gvl(resolve_paths, paths, RUBY_UBF_IO, NULL);
  // Ruby owns filesystem encoding and Unicode normalization semantics.
  if (!paths->ready || !ascii_path(paths->absolute) || !ascii_path(paths->resolved)) return Qnil;

  VALUE absolute;
  if (normalized_path(paths->absolute)) {
    absolute = rb_filesystem_str_new_cstr(paths->absolute);
  } else {
    VALUE directory = paths->directory ? rb_filesystem_str_new_cstr(paths->directory) : Qnil;
    absolute = rb_file_absolute_path(paths->path, directory);
  }
  VALUE result = rb_ary_new_capa(2);
  if (included(StringValueCStr(absolute), paths)) rb_ary_push(result, absolute);
  if (paths->resolved && strcmp(paths->resolved, StringValueCStr(absolute)) != 0 &&
      included(paths->resolved, paths)) {
    rb_ary_push(result, rb_filesystem_str_new_cstr(paths->resolved));
  }
  return result;
}

static VALUE free_paths(VALUE data) {
  struct dependency_paths *paths = (struct dependency_paths *)data;
  free(paths->absolute);
  free(paths->directory);
  free(paths->resolved);
  return Qnil;
}

static VALUE native_paths(VALUE self, VALUE path, VALUE root, VALUE ignored) {
  Check_Type(path, T_STRING);
  Check_Type(root, T_STRING);
  if (!NIL_P(ignored)) Check_Type(ignored, T_STRING);
  if (RSTRING_LEN(root) == 0) return Qnil;
  if (!rb_enc_str_asciionly_p(path) || !rb_enc_str_asciionly_p(root) ||
      (!NIL_P(ignored) && !rb_enc_str_asciionly_p(ignored))) return Qnil;

  const char *input = StringValueCStr(path);
  struct dependency_paths paths = {0};
  paths.path = path;
  paths.root = root;
  paths.ignored = ignored;
  paths.relative = input[0] != '/';
  paths.absolute = strdup(input);
  if (!paths.absolute) return Qnil;
  return rb_ensure(collect_paths, (VALUE)&paths, free_paths, (VALUE)&paths);
}

static VALUE native_file_path(VALUE self, VALUE file) {
  Check_Type(file, T_FILE);
  // File#path can call customer String#initialize_dup. Read Ruby's stored path
  // directly while holding the GVL. The resolver never modifies this string.
  rb_io_t *io = RFILE(file)->fptr;
  return io ? io->pathv : Qnil;
}

void Init_file_dependencies(void) {
  VALUE datadog = rb_define_module("Datadog");
  VALUE ci = rb_define_module_under(datadog, "CI");
  VALUE tia = rb_define_module_under(ci, "TestImpactAnalysis");
  VALUE coverage = rb_define_module_under(tia, "Coverage");
  VALUE dependencies = rb_define_class_under(coverage, "FileDependencies", rb_cObject);
  rb_define_private_method(dependencies, "native_paths", native_paths, 3);
  rb_define_private_method(dependencies, "native_file_path", native_file_path, 1);
}
