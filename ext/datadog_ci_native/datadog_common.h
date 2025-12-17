#ifndef DATADOG_COMMON_H
#define DATADOG_COMMON_H

#include <ruby.h>
#include <stdbool.h>

/* ---- Path filtering ----------------------------------------------------- */

/**
 * Check if a file path is under root_path and not under ignored_path.
 * Returns true if the path should be included, false otherwise.
 *
 * @param path          The file path to check
 * @param root_path     The root path prefix (required)
 * @param root_path_len Length of root_path
 * @param ignored_path  Path prefix to exclude (can be NULL)
 * @param ignored_path_len Length of ignored_path (0 if not set)
 */
bool dd_ci_is_path_included(const char *path, const char *root_path,
                            long root_path_len, const char *ignored_path,
                            long ignored_path_len);

/* ---- Utility functions -------------------------------------------------- */

/**
 * Duplicate a string of given size using Ruby's memory allocator.
 * The returned string is null-terminated.
 */
char *dd_ci_ruby_strndup(const char *str, size_t size);

/**
 * Safe exception handling - equivalent to Ruby's "begin/rescue nil".
 * Calls function_to_call_safely with the given argument and returns Qnil
 * if an exception occurs (clearing the exception state).
 */
VALUE dd_ci_rescue_nil(VALUE (*function_to_call_safely)(VALUE),
                       VALUE function_to_call_safely_arg);

/**
 * Get source location for a given constant name string.
 * Calls Object.const_source_location(const_name_str).
 * Returns an array [filename, lineno] or nil if not found.
 */
VALUE dd_ci_get_const_source_location(VALUE const_name_str);

/**
 * Safely get source location for a given constant name string.
 * Returns Qnil if an exception occurs (e.g., for C-defined or anonymous
 * classes).
 */
VALUE dd_ci_safely_get_const_source_location(VALUE const_name_str);

/**
 * Resolve a constant name to its source file path.
 * Returns the filename (String) where the constant is defined, or Qnil if not
 * found.
 */
VALUE dd_ci_resolve_const_to_file(VALUE const_name_str);

#endif /* DATADOG_COMMON_H */
