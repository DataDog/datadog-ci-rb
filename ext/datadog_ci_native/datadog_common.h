#ifndef DATADOG_COMMON_H
#define DATADOG_COMMON_H

#include <ruby.h>

/* ---- Utility functions -------------------------------------------------- */

/**
 * Duplicate a string of given size using Ruby's memory allocator.
 * The returned string is null-terminated.
 */
char *dd_ruby_strndup(const char *str, size_t size);

/**
 * Safe exception handling - equivalent to Ruby's "begin/rescue nil".
 * Calls function_to_call_safely with the given argument and returns Qnil
 * if an exception occurs (clearing the exception state).
 */
VALUE dd_rescue_nil(VALUE (*function_to_call_safely)(VALUE),
                    VALUE function_to_call_safely_arg);

/**
 * Get source location for a given constant name string.
 * Calls Object.const_source_location(const_name_str).
 * Returns an array [filename, lineno] or nil if not found.
 */
VALUE dd_get_const_source_location(VALUE const_name_str);

/**
 * Safely get source location for a given constant name string.
 * Returns Qnil if an exception occurs (e.g., for C-defined or anonymous
 * classes).
 */
VALUE dd_safely_get_const_source_location(VALUE const_name_str);

/**
 * Resolve a constant name to its source file path.
 * Returns the filename (String) where the constant is defined, or Qnil if not
 * found.
 */
VALUE dd_resolve_const_to_file(VALUE const_name_str);

#endif /* DATADOG_COMMON_H */
