#include "file_dependencies.h"
#include "datadog_common.h"
#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/io.h"
#include "ruby/thread.h"
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/attr.h>
#endif

#if defined(PATH_MAX) && PATH_MAX > 4096
#define DD_PATH_BUF_SIZE PATH_MAX
#else
#define DD_PATH_BUF_SIZE 4096
#endif

static VALUE empty_paths_array = Qnil;

struct dependency_paths {
  VALUE path, root, ignored;
  char *absolute, *directory, *resolved;
  char *absolute_heap, *directory_heap, *resolved_heap;
  size_t absolute_len, resolved_len;
  bool relative, ready;
  char absolute_buf[DD_PATH_BUF_SIZE];
  char directory_buf[DD_PATH_BUF_SIZE];
  char resolved_buf[DD_PATH_BUF_SIZE];
};

// Darwin's getcwd/realpath walk ancestors. FULLPATH resolves through the
// kernel in one call. UNIQUE rejects hard links, for which FULLPATH can return
// a different name; unsupported flags/filesystems fall back to POSIX realpath.
static char *full_path_into(const char *path, char *buf, size_t buf_size,
                            char **heap_out, size_t *len_out) {
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
      if (value[length - 1] == '\0') {
        if (len_out) *len_out = length - 1;
        if (length <= buf_size) {
          memcpy(buf, value, length);
          return buf;
        }
        char *copy = malloc(length);
        if (!copy) return NULL;
        memcpy(copy, value, length);
        *heap_out = copy;
        return copy;
      }
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
    size_t dir_len = 0;
    paths->directory = full_path_into(".", paths->directory_buf,
                                      sizeof(paths->directory_buf),
                                      &paths->directory_heap, &dir_len);
    if (!paths->directory) {
      if (getcwd(paths->directory_buf, sizeof(paths->directory_buf)) != NULL) {
        paths->directory = paths->directory_buf;
        dir_len = strlen(paths->directory);
      } else {
        paths->directory_heap = getcwd(NULL, 0);
        paths->directory = paths->directory_heap;
        if (!paths->directory) return NULL;
        dir_len = strlen(paths->directory);
      }
    }
    size_t abs_len = paths->absolute_len;
    size_t joined_len = dir_len + 1 + abs_len;
    if (joined_len + 1 <= sizeof(paths->absolute_buf) &&
        paths->absolute == paths->absolute_buf) {
      memmove(paths->absolute_buf + dir_len + 1, paths->absolute_buf,
              abs_len + 1);
      memcpy(paths->absolute_buf, paths->directory, dir_len);
      paths->absolute_buf[dir_len] = '/';
      paths->absolute_len = joined_len;
    } else {
      char *joined = malloc(joined_len + 1);
      if (!joined) return NULL;
      memcpy(joined, paths->directory, dir_len);
      joined[dir_len] = '/';
      memcpy(joined + dir_len + 1, paths->absolute, abs_len + 1);
      free(paths->absolute_heap);
      paths->absolute_heap = joined;
      paths->absolute = joined;
      paths->absolute_len = joined_len;
    }
  }
  // Preserve .. until after symlinks have been followed.
  errno = 0;
  paths->resolved = full_path_into(paths->absolute, paths->resolved_buf,
                                   sizeof(paths->resolved_buf),
                                   &paths->resolved_heap, &paths->resolved_len);
  if (!paths->resolved && errno != ENOENT && errno != ENOTDIR) {
    if (realpath(paths->absolute, paths->resolved_buf) != NULL) {
      paths->resolved = paths->resolved_buf;
      paths->resolved_len = strlen(paths->resolved);
    } else if (errno == ENAMETOOLONG) {
      paths->resolved_heap = realpath(paths->absolute, NULL);
      paths->resolved = paths->resolved_heap;
      if (paths->resolved) paths->resolved_len = strlen(paths->resolved);
    }
  }
  paths->ready = true;
  return NULL;
}

static bool ascii_path_len(const char *path, size_t len) {
  if (!path) return true;
  const unsigned char *p = (const unsigned char *)path;
  for (size_t i = 0; i < len; i++) {
    if (p[i] >= 128) return false;
  }
  return true;
}

// Avoid allocating a base string and invoking Ruby's path normalizer when
// the absolute spelling is already normalized. All other shapes use Ruby.
static bool normalized_path(const char *path) {
  const char *segment = path + 1;
  for (const char *p = segment;; p++) {
    if (*p != '/' && *p != '\0') continue;
    size_t length = (size_t)(p - segment);
    if (length == 0 || (length == 1 && segment[0] == '.') ||
        (length == 2 && segment[0] == '.' && segment[1] == '.')) return false;
    if (*p == '\0') return true;
    segment = p + 1;
  }
}

static inline bool included_len(const char *path, size_t len,
                                struct dependency_paths *paths) {
  return dd_ci_is_path_included(
      path, (long)len, RSTRING_PTR(paths->root), RSTRING_LEN(paths->root),
      NIL_P(paths->ignored) ? NULL : RSTRING_PTR(paths->ignored),
      NIL_P(paths->ignored) ? 0 : RSTRING_LEN(paths->ignored));
}

static VALUE collect_paths(VALUE data) {
  struct dependency_paths *paths = (struct dependency_paths *)data;
  rb_thread_call_without_gvl(resolve_paths, paths, RUBY_UBF_IO, NULL);
  // Ruby owns filesystem encoding and Unicode normalization semantics.
  if (!paths->ready ||
      !ascii_path_len(paths->absolute, paths->absolute_len) ||
      !ascii_path_len(paths->resolved, paths->resolved_len)) {
    return Qnil;
  }

  if (normalized_path(paths->absolute)) {
    bool abs_included = included_len(paths->absolute, paths->absolute_len, paths);
    bool res_included =
        paths->resolved != NULL &&
        (paths->resolved_len != paths->absolute_len ||
         memcmp(paths->resolved, paths->absolute, paths->resolved_len) != 0) &&
        included_len(paths->resolved, paths->resolved_len, paths);

    if (!abs_included && !res_included) {
      return empty_paths_array;
    }

    VALUE result = rb_ary_new_capa(abs_included && res_included ? 2 : 1);
    if (abs_included) {
      rb_ary_push(result, rb_filesystem_str_new(paths->absolute,
                                                (long)paths->absolute_len));
    }
    if (res_included) {
      rb_ary_push(result, rb_filesystem_str_new(paths->resolved,
                                                (long)paths->resolved_len));
    }
    return result;
  }

  VALUE directory =
      paths->directory ? rb_filesystem_str_new_cstr(paths->directory) : Qnil;
  VALUE absolute = rb_file_absolute_path(paths->path, directory);
  const char *abs_cstr = StringValueCStr(absolute);
  size_t abs_cstr_len = (size_t)RSTRING_LEN(absolute);

  bool abs_included = included_len(abs_cstr, abs_cstr_len, paths);
  bool res_included =
      paths->resolved != NULL &&
      (paths->resolved_len != abs_cstr_len ||
       memcmp(paths->resolved, abs_cstr, paths->resolved_len) != 0) &&
      included_len(paths->resolved, paths->resolved_len, paths);

  if (!abs_included && !res_included) {
    return empty_paths_array;
  }

  VALUE result = rb_ary_new_capa(abs_included && res_included ? 2 : 1);
  if (abs_included) rb_ary_push(result, absolute);
  if (res_included) {
    rb_ary_push(result, rb_filesystem_str_new(paths->resolved,
                                              (long)paths->resolved_len));
  }
  return result;
}

static VALUE free_paths(VALUE data) {
  struct dependency_paths *paths = (struct dependency_paths *)data;
  free(paths->absolute_heap);
  free(paths->directory_heap);
  free(paths->resolved_heap);
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
  size_t input_len = (size_t)RSTRING_LEN(path);

  struct dependency_paths paths;
  paths.path = path;
  paths.root = root;
  paths.ignored = ignored;
  paths.directory = NULL;
  paths.resolved = NULL;
  paths.absolute_heap = NULL;
  paths.directory_heap = NULL;
  paths.resolved_heap = NULL;
  paths.absolute_len = input_len;
  paths.resolved_len = 0;
  paths.relative = input[0] != '/';
  paths.ready = false;

  if (input_len + 1 <= sizeof(paths.absolute_buf)) {
    memcpy(paths.absolute_buf, input, input_len + 1);
    paths.absolute = paths.absolute_buf;
  } else {
    paths.absolute_heap = malloc(input_len + 1);
    if (!paths.absolute_heap) return Qnil;
    memcpy(paths.absolute_heap, input, input_len + 1);
    paths.absolute = paths.absolute_heap;
  }

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
  empty_paths_array = rb_ary_new_capa(0);
  rb_obj_freeze(empty_paths_array);
  rb_gc_register_mark_object(empty_paths_array);

  VALUE datadog = rb_define_module("Datadog");
  VALUE ci = rb_define_module_under(datadog, "CI");
  VALUE tia = rb_define_module_under(ci, "TestImpactAnalysis");
  VALUE coverage = rb_define_module_under(tia, "Coverage");
  VALUE dependencies = rb_define_class_under(coverage, "FileDependencies", rb_cObject);
  rb_define_private_method(dependencies, "native_paths", native_paths, 3);
  rb_define_private_method(dependencies, "native_file_path", native_file_path, 1);
}
