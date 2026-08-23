#ifndef SLINT_COMPILER_FFI_H
#define SLINT_COMPILER_FFI_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef void *slint_compiler_todo_handle;

typedef void (*slint_compiler_callback_add_todo)(void *user_data, const char *text);

typedef void (*slint_compiler_callback_toggle_todo)(void *user_data, int32_t index, bool checked);

typedef void (*slint_compiler_callback_remove_done)(void *user_data);

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

char *slint_compiler_last_error(void);

void slint_compiler_string_free(char *s);

slint_compiler_todo_handle slint_compiler_todo_new(void);

void slint_compiler_todo_free(slint_compiler_todo_handle handle);

void slint_compiler_todo_set_size(slint_compiler_todo_handle handle,
                                  uint32_t width,
                                  uint32_t height);

bool slint_compiler_todo_render(slint_compiler_todo_handle handle, uint8_t *buffer, uintptr_t len);

void slint_compiler_todo_pointer_event(slint_compiler_todo_handle handle,
                                       uint8_t kind,
                                       float x,
                                       float y,
                                       uint8_t button,
                                       float dx,
                                       float dy);

void slint_compiler_todo_key_event(slint_compiler_todo_handle handle,
                                   const char *text,
                                   bool pressed);

char *slint_compiler_todo_get_model(slint_compiler_todo_handle handle);

bool slint_compiler_todo_set_model(slint_compiler_todo_handle handle, const char *json);

bool slint_compiler_todo_on_add_todo(slint_compiler_todo_handle handle,
                                     slint_compiler_callback_add_todo cb,
                                     void *user_data);

bool slint_compiler_todo_on_toggle_todo(slint_compiler_todo_handle handle,
                                        slint_compiler_callback_toggle_todo cb,
                                        void *user_data);

bool slint_compiler_todo_on_remove_done(slint_compiler_todo_handle handle,
                                        slint_compiler_callback_remove_done cb,
                                        void *user_data);

bool slint_compiler_todo_invoke_add_todo(slint_compiler_todo_handle handle, const char *text);

bool slint_compiler_todo_invoke_toggle_todo(slint_compiler_todo_handle handle,
                                            int32_t index,
                                            bool checked);

bool slint_compiler_todo_invoke_remove_done(slint_compiler_todo_handle handle);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* SLINT_COMPILER_FFI_H */
