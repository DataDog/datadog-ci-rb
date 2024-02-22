#include <ruby.h>
#include <ruby/debug.h>
#include <stdio.h>

static ID id_puts;

static void kernel_puts(VALUE val)
{
  rb_funcall(rb_mKernel, id_puts, 1, val);
}

VALUE DDCovClass = Qnil;

VALUE dd_cov_initialize(VALUE self)
{
  rb_iv_set(self, "@var", rb_hash_new());
  return self;
}

void dd_cov_update_line_coverage(rb_event_flag_t event, VALUE data, VALUE self, ID id, VALUE klass)
{
  printf("EVENT HOOK FIRED\n");
  printf("FILE: %s\n", rb_sourcefile());
  printf("LINE: %d\n", rb_sourceline());
  kernel_puts(klass);
  // kernel_puts(event);
  // kernel_puts(data);
  // kernel_puts(self);
  // kernel_puts(id);
}

VALUE dd_cov_start(VALUE self)
{
  // get current thread
  VALUE thval = rb_thread_current();

  // add event hook
  rb_thread_add_event_hook(thval, dd_cov_update_line_coverage, RUBY_EVENT_LINE, Qnil);

  return self;
}

VALUE dd_cov_stop(VALUE self)
{
  // get current thread
  VALUE thval = rb_thread_current();

  // remove event hook
  rb_thread_remove_event_hook(thval, dd_cov_update_line_coverage);
  return self;
}

void Init_ddcov(void)
{
  id_puts = rb_intern("puts");

  DDCovClass = rb_define_class("DDCov", rb_cObject);
  rb_define_method(DDCovClass, "initialize", dd_cov_initialize, 0);
  rb_define_method(DDCovClass, "start", dd_cov_start, 0);
  rb_define_method(DDCovClass, "stop", dd_cov_stop, 0);
}
