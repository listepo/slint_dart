#ifndef SLINT_SKIA_FFI_H
#define SLINT_SKIA_FFI_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

const char *slint_skia_last_error(void);

void slint_skia_string_free(char *s);

void *slint_skia_engine_new(void);

void slint_skia_engine_free(void *engine);

void *slint_skia_engine_compile(void *engine, const char *source, const char *path);

uintptr_t slint_skia_definitions_count(void *engine);

char *slint_skia_definitions_name(void *_engine, uintptr_t _index);

void slint_skia_definitions_free(void *_definitions);

void *slint_skia_instantiate(void *definition);

void slint_skia_instance_free(void *instance);

bool slint_skia_instance_set_size(void *instance, float width, float height);

bool slint_skia_instance_render(void *instance);

int64_t slint_skia_instance_texture_id(void *instance);

bool slint_skia_instance_pointer_event(void *instance,
                                       uint8_t kind,
                                       float x,
                                       float y,
                                       uint8_t button,
                                       float dx,
                                       float dy);

bool slint_skia_instance_key_event(void *instance, const char *text, bool pressed);

char *slint_skia_instance_get_property(void *instance, const char *name);

bool slint_skia_instance_set_property(void *instance, const char *name, const char *value_json);

char *slint_skia_instance_invoke(void *instance, const char *name, const char *args_json);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* SLINT_SKIA_FFI_H */
