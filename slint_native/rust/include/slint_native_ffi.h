#ifndef SLINT_NATIVE_FFI_H
#define SLINT_NATIVE_FFI_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef void *SlintNativeEngine;

typedef void *SlintNativeDefinitionList;

typedef void *SlintNativeInstance;

typedef void (*SlintNativeCallbackFn)(void *user_data, const char *args_json);

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

SlintNativeEngine slint_native_engine_new(void);

void slint_native_engine_free(SlintNativeEngine engine);

SlintNativeDefinitionList slint_native_engine_compile(SlintNativeEngine engine,
                                                      const char *source,
                                                      const char *path);

uint32_t slint_native_definitions_count(SlintNativeDefinitionList list);

char *slint_native_definitions_name(SlintNativeDefinitionList list, uint32_t index);

/**
 * Public properties of definition `index` as a JSON array
 * `[{"name": "...", "type": "..."}]`. Free with slint_native_string_free.
 */
char *slint_native_definitions_properties_json(SlintNativeDefinitionList list, uint32_t index);

/**
 * Public callback names of definition `index` as a JSON string array.
 * Free with slint_native_string_free.
 */
char *slint_native_definitions_callbacks_json(SlintNativeDefinitionList list, uint32_t index);

void slint_native_definitions_free(SlintNativeDefinitionList list);

SlintNativeInstance slint_native_instantiate(SlintNativeDefinitionList list, uint32_t index);

void slint_native_instance_free(SlintNativeInstance instance);

void slint_native_instance_set_size(SlintNativeInstance instance, uint32_t width, uint32_t height);

bool slint_native_instance_render(SlintNativeInstance instance, uint8_t *buffer, uintptr_t len);

void slint_native_instance_pointer_event(SlintNativeInstance instance,
                                         uint8_t kind,
                                         float x,
                                         float y,
                                         uint8_t button,
                                         float dx,
                                         float dy);

void slint_native_instance_key_event(SlintNativeInstance instance, const char *text, bool pressed);

char *slint_native_instance_get_property(SlintNativeInstance instance, const char *name);

bool slint_native_instance_set_property(SlintNativeInstance instance,
                                        const char *name,
                                        const char *json);

char *slint_native_instance_invoke(SlintNativeInstance instance,
                                   const char *name,
                                   const char *args_json);

bool slint_native_instance_set_callback(SlintNativeInstance instance,
                                        const char *name,
                                        SlintNativeCallbackFn cb,
                                        void *user_data);

void slint_native_string_free(char *s);

char *slint_native_last_error(void);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* SLINT_NATIVE_FFI_H */
