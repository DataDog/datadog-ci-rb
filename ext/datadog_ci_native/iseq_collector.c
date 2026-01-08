#include <ruby.h>

#include "imemo_helpers.h"
#include "ruby_internal.h"

/*
 * Callback for rb_objspace_each_objects.
 *
 * The callback receives a range of object slots [vstart, vend) with given
 * stride. Each slot may contain a live object, a freed slot, or garbage.
 * We check each slot for ISeq objects and add them to the result array.
 *
 * See:
 * https://github.com/ruby/ruby/blob/c99670d6683fec770271d35c2ae082514b1abce3/gc.c#L3550
 */
static int collect_iseqs_callback(void *vstart, void *vend, size_t stride,
                                  void *data) {
  VALUE iseqs_array = (VALUE)data;

  for (VALUE v = (VALUE)vstart; v != (VALUE)vend; v += stride) {
    if (dd_ci_imemo_iseq_p(v)) {
      VALUE iseq = rb_iseqw_new((void *)v);
      rb_ary_push(iseqs_array, iseq);
    }
  }
  return 0;
}

/*
 * ISeqCollector.collect_iseqs
 *
 * Walk all live objects in the Ruby object space and collect all
 * instruction sequences (ISeqs) into an array.
 *
 * @return [Array<RubyVM::InstructionSequence>] Array of all live ISeqs
 *
 * NOTE:
 * - Only sees ISeqs that still exist (top-level file ISeqs might be GC'd).
 *   Method ISeqs usually survive longer.
 * - The returned ISeqs include all types: method bodies, class bodies,
 *   blocks, etc.

 * It is very similar to iseq_collector from debug gem:
 * https://github.com/ruby/debug/blob/master/ext/debug/iseq_collector.c
*/

static VALUE iseq_collector_collect(VALUE self) {
  VALUE iseqs_array = rb_ary_new();

  rb_objspace_each_objects(collect_iseqs_callback, (void *)iseqs_array);

  return iseqs_array;
}

/* ---- Module initialization ---------------------------------------------- */

void Init_iseq_collector(void) {
  VALUE mDatadog = rb_define_module("Datadog");
  VALUE mCI = rb_define_module_under(mDatadog, "CI");
  VALUE mSourceCode = rb_define_module_under(mCI, "SourceCode");
  VALUE mISeqCollector = rb_define_module_under(mSourceCode, "ISeqCollector");

  rb_define_singleton_method(mISeqCollector, "collect_iseqs",
                             iseq_collector_collect, 0);
}
