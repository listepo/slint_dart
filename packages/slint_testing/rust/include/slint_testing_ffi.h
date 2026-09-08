#ifndef SLINT_TESTING_FFI_H
#define SLINT_TESTING_FFI_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef void *SlintTestingApp;

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * Last error, or null. Caller frees with [slint_testing_string_free].
 */
char *slint_testing_last_error(void);

void slint_testing_string_free(char *s);

/**
 * Advances the testing backend's mock clock, driving animations and timers.
 */
void slint_testing_elapse_ms(uint64_t millis);

/**
 * Compiles `source` and instantiates `component` on the testing backend.
 * `component` may be null only when the source exports exactly one.
 */
SlintTestingApp slint_testing_app_new(const char *source, const char *path, const char *component);

void slint_testing_app_free(SlintTestingApp app);

/**
 * Runs a query and returns its matches as a JSON array of element
 * descriptors, replacing the previous snapshot. `kind` is one of `label`,
 * `id`, `type`, or `all`; `needle` is ignored for `all`.
 *
 * Caller frees with [slint_testing_string_free]; null means error.
 */
char *slint_testing_app_query(SlintTestingApp app, const char *kind, const char *needle);

/**
 * Invokes the accessible default action of the element at `index` in the
 * last query's snapshot — a button press, a checkbox toggle.
 */
bool slint_testing_app_click(SlintTestingApp app, uintptr_t index);

/**
 * Sets the accessible value of the element at `index` — typing into a text
 * input, moving a slider.
 */
bool slint_testing_app_set_value(SlintTestingApp app, uintptr_t index, const char *value);

/**
 * Property read; returns JSON. Caller frees with [slint_testing_string_free].
 */
char *slint_testing_app_get_property(SlintTestingApp app, const char *name);

bool slint_testing_app_set_property(SlintTestingApp app, const char *name, const char *json);

/**
 * Invokes a callback or function on the component; returns its result as
 * JSON. Caller frees with [slint_testing_string_free].
 */
char *slint_testing_app_invoke(SlintTestingApp app, const char *name, const char *args_json);

/**
 * Starts recording invocations of `name` into the call log. Tests assert on
 * the log instead of registering a Dart closure, which keeps the whole
 * surface synchronous and free of callback trampolines.
 */
bool slint_testing_app_record(SlintTestingApp app, const char *name);

/**
 * Drains the call log as a JSON array of `{"name": …, "args": […]}`.
 * Caller frees with [slint_testing_string_free].
 */
char *slint_testing_app_take_calls(SlintTestingApp app);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* SLINT_TESTING_FFI_H */
