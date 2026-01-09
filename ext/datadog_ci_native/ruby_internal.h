#ifndef RUBY_INTERNAL_H
#define RUBY_INTERNAL_H

#include <ruby.h>

/*
 * Ruby MRI internal functions and structures.
 *
 * These are not part of Ruby's public C API and are resolved via dynamic
 * linking against libruby. They may change between Ruby versions.
 */

/* ---- ISeq structures and functions -------------------------------------- */

typedef struct rb_iseq_struct rb_iseq_t;

/**
 * Convert an ISeq wrapper VALUE to internal rb_iseq_t pointer.
 */
const rb_iseq_t *rb_iseqw_to_iseq(VALUE iseqw);

/**
 * Get code location (line/column info) from an ISeq.
 */
void rb_iseq_code_location(const rb_iseq_t *iseq, int *first_lineno,
                           int *first_column, int *last_lineno,
                           int *last_column);

/**
 * Wrap an internal iseq pointer as RubyVM::InstructionSequence.
 */
VALUE rb_iseqw_new(const void *iseq);

/* ---- Object space functions --------------------------------------------- */

/**
 * Check if an object is internal (not visible to Ruby code).
 */
int rb_objspace_internal_object_p(VALUE obj);

/**
 * Iterate over all objects in the Ruby object space.
 */
void rb_objspace_each_objects(int (*callback)(void *start, void *end,
                                              size_t stride, void *data),
                              void *data);

#endif /* RUBY_INTERNAL_H */
