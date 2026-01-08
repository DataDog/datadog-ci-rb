#ifndef IMEMO_HELPERS_H
#define IMEMO_HELPERS_H

#include <ruby.h>
#include <stdbool.h>

/*
  Here we are using the same trick that debug gem uses here:

  https://github.com/ruby/debug/blob/master/ext/debug/iseq_collector.c

  These functions allow us to check if the VALUE is an ISeq object
*/

/*
 * IMEMO (internal memo) helpers for working with Ruby's internal objects.
 */

#define DD_CI_IMEMO_TYPE_ISEQ 7
#define DD_CI_IMEMO_MASK 0x0f

/**
 * Get the IMEMO type from flags.
 */
int dd_ci_imemo_type(VALUE imemo);

/**
 * Check if a VALUE is an internal ISeq object.
 */
bool dd_ci_imemo_iseq_p(VALUE v);

#endif /* IMEMO_HELPERS_H */
