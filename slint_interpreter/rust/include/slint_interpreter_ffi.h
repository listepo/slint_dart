#ifndef SLINT_INTERPRETER_FFI_H
#define SLINT_INTERPRETER_FFI_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef void *SlintInterpreterEngine;

typedef void *SlintInterpreterDefinitionList;

typedef void *SlintInterpreterInstance;

typedef void (*SlintInterpreterCallbackFn)(void *user_data, const char *args_json);

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

SlintInterpreterEngine slint_interpreter_engine_new(void);

void slint_interpreter_engine_free(SlintInterpreterEngine engine);

SlintInterpreterDefinitionList slint_interpreter_engine_compile(SlintInterpreterEngine engine,
                                                                const char *source,
                                                                const char *path);

uint32_t slint_interpreter_definitions_count(SlintInterpreterDefinitionList list);

char *slint_interpreter_definitions_name(SlintInterpreterDefinitionList list, uint32_t index);

void slint_interpreter_definitions_free(SlintInterpreterDefinitionList list);

SlintInterpreterInstance slint_interpreter_instantiate(SlintInterpreterDefinitionList list,
                                                       uint32_t index);

void slint_interpreter_instance_free(SlintInterpreterInstance instance);

void slint_interpreter_instance_set_size(SlintInterpreterInstance instance,
                                         uint32_t width,
                                         uint32_t height);

bool slint_interpreter_instance_render(SlintInterpreterInstance instance,
                                       uint8_t *buffer,
                                       uintptr_t len);

void slint_interpreter_instance_pointer_event(SlintInterpreterInstance instance,
                                              uint8_t kind,
                                              float x,
                                              float y,
                                              uint8_t button,
                                              float dx,
                                              float dy);

void slint_interpreter_instance_key_event(SlintInterpreterInstance instance,
                                          const char *text,
                                          bool pressed);

char *slint_interpreter_instance_get_property(SlintInterpreterInstance instance, const char *name);

bool slint_interpreter_instance_set_property(SlintInterpreterInstance instance,
                                             const char *name,
                                             const char *json);

char *slint_interpreter_instance_invoke(SlintInterpreterInstance instance,
                                        const char *name,
                                        const char *args_json);

bool slint_interpreter_instance_set_callback(SlintInterpreterInstance instance,
                                             const char *name,
                                             SlintInterpreterCallbackFn cb,
                                             void *user_data);

void slint_interpreter_string_free(char *s);

char *slint_interpreter_last_error(void);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* SLINT_INTERPRETER_FFI_H */
