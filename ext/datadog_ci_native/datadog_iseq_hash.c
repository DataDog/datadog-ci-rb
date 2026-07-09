#include "datadog_iseq_hash.h"
#include "ruby.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define FNV64_OFFSET_BASIS UINT64_C(14695981039346656037)
#define FNV64_PRIME UINT64_C(1099511628211)

static VALUE rb_mSourceCode;
static VALUE rb_cInstructionSequence;
static VALUE rb_sSimpleDataFormat;
static VALUE rb_sym_mid;
static VALUE rb_sym_flag;
static VALUE rb_sym_orig_argc;

static ID id_of;
static ID id_to_a;
static ID id_mid;
static ID id_flag;
static ID id_orig_argc;
static ID id_source;
static ID id_options;
static ID id_begin;
static ID id_end;
static ID id_exclude_end_p;
static ID id_to_s;
static ID id_inspect;
static ID id_name;

static void hash_value(uint64_t *hash, VALUE value);

static void hash_bytes(uint64_t *hash, const char *bytes, long length) {
  for (long i = 0; i < length; i++) {
    *hash ^= (unsigned char)bytes[i];
    *hash *= FNV64_PRIME;
  }
}

static void hash_cstr(uint64_t *hash, const char *value) {
  hash_bytes(hash, value, (long)strlen(value));
}

static void hash_tag(uint64_t *hash, const char *tag) {
  hash_cstr(hash, tag);
  hash_bytes(hash, "\0", 1);
}

static void hash_long_long(uint64_t *hash, long long value) {
  char buffer[32];
  int length = snprintf(buffer, sizeof(buffer), "%lld", value);
  hash_bytes(hash, buffer, length);
  hash_bytes(hash, "\0", 1);
}

static void hash_string(uint64_t *hash, VALUE value) {
  hash_long_long(hash, RSTRING_LEN(value));
  hash_bytes(hash, RSTRING_PTR(value), RSTRING_LEN(value));
  hash_bytes(hash, "\0", 1);
}

static void hash_string_method(uint64_t *hash, VALUE value, ID method_id) {
  VALUE string = rb_funcall(value, method_id, 0);

  if (NIL_P(string)) {
    hash_tag(hash, "nil");
    return;
  }

  StringValue(string);
  hash_string(hash, string);
}

static int iseq_array_p(VALUE value) {
  if (!RB_TYPE_P(value, T_ARRAY) || RARRAY_LEN(value) == 0) {
    return 0;
  }

  VALUE format = rb_ary_entry(value, 0);
  return RB_TYPE_P(format, T_STRING) && rb_str_cmp(format, rb_sSimpleDataFormat) == 0;
}

static void hash_iseq_array(uint64_t *hash, VALUE iseq_array);

static void hash_array(uint64_t *hash, VALUE value) {
  if (iseq_array_p(value)) {
    hash_iseq_array(hash, value);
    return;
  }

  hash_tag(hash, "array");
  hash_long_long(hash, RARRAY_LEN(value));

  for (long i = 0; i < RARRAY_LEN(value); i++) {
    hash_value(hash, rb_ary_entry(value, i));
  }
}

struct hash_pair_state {
  uint64_t *hash;
};

static int hash_pair(VALUE key, VALUE value, VALUE data) {
  struct hash_pair_state *state = (struct hash_pair_state *)data;

  hash_value(state->hash, key);
  hash_value(state->hash, value);

  return ST_CONTINUE;
}

static void hash_hash(uint64_t *hash, VALUE value) {
  if (RHASH_SIZE(value) == 3) {
    VALUE mid = rb_hash_lookup2(value, rb_sym_mid, Qundef);
    VALUE flag = rb_hash_lookup2(value, rb_sym_flag, Qundef);
    VALUE orig_argc = rb_hash_lookup2(value, rb_sym_orig_argc, Qundef);

    if (mid != Qundef && flag != Qundef && orig_argc != Qundef) {
      hash_tag(hash, "call");
      hash_value(hash, mid);
      hash_value(hash, flag);
      hash_value(hash, orig_argc);
      return;
    }
  }

  hash_tag(hash, "hash");
  hash_long_long(hash, RHASH_SIZE(value));

  struct hash_pair_state state = {hash};
  rb_hash_foreach(value, hash_pair, (VALUE)&state);
}

static void hash_symbol(uint64_t *hash, VALUE value) {
  const char *name = rb_id2name(SYM2ID(value));

  hash_tag(hash, "symbol");
  if (name == NULL) {
    hash_tag(hash, "unknown");
    return;
  }

  hash_cstr(hash, name);
  hash_bytes(hash, "\0", 1);
}

static void hash_integer(uint64_t *hash, VALUE value) {
  hash_tag(hash, "integer");

  if (FIXNUM_P(value)) {
    hash_long_long(hash, FIX2LONG(value));
    return;
  }

  hash_string_method(hash, value, id_to_s);
}

static void hash_regexp(uint64_t *hash, VALUE value) {
  hash_tag(hash, "regexp");
  hash_string_method(hash, value, id_source);
  hash_value(hash, rb_funcall(value, id_options, 0));
}

static void hash_range(uint64_t *hash, VALUE value) {
  hash_tag(hash, "range");
  hash_value(hash, rb_funcall(value, id_begin, 0));
  hash_value(hash, rb_funcall(value, id_end, 0));
  hash_value(hash, rb_funcall(value, id_exclude_end_p, 0));
}

static void hash_object(uint64_t *hash, VALUE value) {
  hash_tag(hash, "object");
  hash_string_method(hash, rb_obj_class(value), id_name);
  hash_string_method(hash, value, id_inspect);
}

static void hash_value(uint64_t *hash, VALUE value) {
  switch (TYPE(value)) {
    case T_ARRAY:
      hash_array(hash, value);
      break;
    case T_HASH:
      hash_hash(hash, value);
      break;
    case T_SYMBOL:
      hash_symbol(hash, value);
      break;
    case T_STRING:
      hash_tag(hash, "string");
      hash_string(hash, value);
      break;
    case T_FIXNUM:
    case T_BIGNUM:
      hash_integer(hash, value);
      break;
    case T_FLOAT:
      hash_tag(hash, "float");
      hash_string_method(hash, value, id_to_s);
      break;
    case T_TRUE:
      hash_tag(hash, "true");
      break;
    case T_FALSE:
      hash_tag(hash, "false");
      break;
    case T_NIL:
      hash_tag(hash, "nil");
      break;
    default:
      if (rb_obj_is_kind_of(value, rb_cRegexp)) {
        hash_regexp(hash, value);
      } else if (rb_obj_is_kind_of(value, rb_cRange)) {
        hash_range(hash, value);
      } else {
        hash_object(hash, value);
      }
      break;
  }
}

static void hash_body(uint64_t *hash, VALUE body) {
  if (!RB_TYPE_P(body, T_ARRAY)) {
    hash_value(hash, body);
    return;
  }

  hash_tag(hash, "body");

  for (long i = 0; i < RARRAY_LEN(body); i++) {
    VALUE entry = rb_ary_entry(body, i);

    if (RB_INTEGER_TYPE_P(entry) || RB_TYPE_P(entry, T_SYMBOL)) {
      continue;
    }

    hash_value(hash, entry);
  }
}

static void hash_iseq_array(uint64_t *hash, VALUE iseq_array) {
  if (!iseq_array_p(iseq_array)) {
    hash_value(hash, iseq_array);
    return;
  }

  hash_tag(hash, "iseq");
  hash_value(hash, rb_ary_entry(iseq_array, 9));
  hash_value(hash, rb_ary_entry(iseq_array, 10));
  hash_value(hash, rb_ary_entry(iseq_array, 11));
  hash_value(hash, rb_ary_entry(iseq_array, 12));
  hash_body(hash, rb_ary_entry(iseq_array, 13));
}

static VALUE iseq_hash_from_iseq(VALUE self, VALUE iseqw) {
  VALUE iseq_array = rb_funcall(iseqw, id_to_a, 0);
  uint64_t hash = FNV64_OFFSET_BASIS;

  hash_iseq_array(&hash, iseq_array);

  char buffer[17];
  snprintf(buffer, sizeof(buffer), "%016" PRIx64, hash);

  return rb_usascii_str_new(buffer, 16);
}

static VALUE iseq_hash_from_target(VALUE self, VALUE target) {
  if (NIL_P(target)) {
    return Qnil;
  }

  VALUE iseqw = target;
  if (CLASS_OF(target) != rb_cInstructionSequence) {
    iseqw = rb_funcall(rb_cInstructionSequence, id_of, 1, target);
  }

  if (NIL_P(iseqw)) {
    return Qnil;
  }

  return iseq_hash_from_iseq(self, iseqw);
}

void Init_datadog_iseq_hash(void) {
  VALUE rb_mDatadog = rb_define_module("Datadog");
  VALUE rb_mCI = rb_define_module_under(rb_mDatadog, "CI");
  VALUE rb_mRubyVM = rb_const_get(rb_cObject, rb_intern("RubyVM"));
  rb_mSourceCode = rb_define_module_under(rb_mCI, "SourceCode");
  rb_cInstructionSequence = rb_const_get(rb_mRubyVM, rb_intern("InstructionSequence"));
  rb_sSimpleDataFormat = rb_str_freeze(rb_str_new_cstr("YARVInstructionSequence/SimpleDataFormat"));
  rb_global_variable(&rb_cInstructionSequence);
  rb_global_variable(&rb_sSimpleDataFormat);

  id_of = rb_intern("of");
  id_to_a = rb_intern("to_a");
  id_mid = rb_intern("mid");
  id_flag = rb_intern("flag");
  id_orig_argc = rb_intern("orig_argc");
  rb_sym_mid = ID2SYM(id_mid);
  rb_sym_flag = ID2SYM(id_flag);
  rb_sym_orig_argc = ID2SYM(id_orig_argc);
  id_source = rb_intern("source");
  id_options = rb_intern("options");
  id_begin = rb_intern("begin");
  id_end = rb_intern("end");
  id_exclude_end_p = rb_intern("exclude_end?");
  id_to_s = rb_intern("to_s");
  id_inspect = rb_intern("inspect");
  id_name = rb_intern("name");

  rb_define_singleton_method(rb_mSourceCode, "_native_iseq_hash", iseq_hash_from_target, 1);
  rb_define_singleton_method(rb_mSourceCode, "_native_iseq_hash_from_iseq", iseq_hash_from_iseq, 1);
}
