#ifndef IMEMO_HELPERS_H
#define IMEMO_HELPERS_H

#include <ruby.h>
#include <stdbool.h>

/*
 * IMEMO (internal memo) helpers for working with Ruby's internal objects.
 */

#define DD_IMEMO_TYPE_ISEQ 7
#define DD_IMEMO_MASK 0x0f

/**
 * Get the IMEMO type from flags.
 */
int dd_imemo_type(VALUE imemo);

/**
 * Check if a VALUE is an internal ISeq object.
 */
bool dd_imemo_iseq_p(VALUE v);

#endif /* IMEMO_HELPERS_H */
