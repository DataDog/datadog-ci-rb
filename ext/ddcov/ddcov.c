#include <ruby.h>

static ID id_puts, id_each;

static void kernel_puts(VALUE val)
{
  rb_funcall(rb_mKernel, id_puts, 1, val);
}

static VALUE my_fixed_args_method(VALUE self, VALUE arg1, VALUE arg2)
{
  kernel_puts(self);
  kernel_puts(arg1);
  kernel_puts(arg2);

  return Qnil;
}

static VALUE my_var_args_c_array_method(int argc, VALUE *argv, VALUE self)
{
  kernel_puts(self);

  for (int i = 0; i < argc; i++)
  {
    kernel_puts(argv[i]);
  }

  return Qnil;
}

static VALUE my_var_args_rb_array_method(VALUE self, VALUE args)
{
  kernel_puts(self);
  kernel_puts(args);

  return Qnil;
}

static VALUE my_method_with_required_block(VALUE self)
{
  VALUE block_ret = rb_yield_values(0);
  kernel_puts(block_ret);

  return Qnil;
}

static VALUE array_puts_every_other_i(VALUE yielded_arg, VALUE data, int argc, const VALUE *argv, VALUE blockarg)
{
  int *puts_cur_ptr = (int *)data;
  int puts_cur = *puts_cur_ptr;

  if (puts_cur)
  {
    kernel_puts(yielded_arg);
  }

  *puts_cur_ptr = !puts_cur;

  return Qnil;
}

static VALUE array_puts_every_other(VALUE self)
{
  int puts_cur = 1;

  rb_block_call(self, id_each, 0, NULL, array_puts_every_other_i, (VALUE)&puts_cur);

  return Qnil;
}

void Init_ddcov(void)
{
  id_puts = rb_intern("puts");

  rb_define_method(rb_cObject, "my_fixed_args_method", my_fixed_args_method, 2);
  rb_define_method(rb_cObject, "my_var_args_c_array_method", my_var_args_c_array_method, -1);
  rb_define_method(rb_cObject, "my_var_args_rb_array_method", my_var_args_rb_array_method, -2);
  rb_define_method(rb_cObject, "my_method_with_required_block", my_method_with_required_block, 0);

  id_each = rb_intern("each");

  rb_define_method(rb_cArray, "puts_every_other", array_puts_every_other, 0);
}
