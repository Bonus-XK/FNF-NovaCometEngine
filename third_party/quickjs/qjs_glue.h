#pragma once

#include <hxcpp.h>
#include "quickjs.h"

/* Haxe -> C++ bridge: (callbackName, jsonArguments) -> jsonResult.
 * Matches cpp.Callable<String->String->String> on the Haxe side.
 */
typedef ::cpp::Function< ::String(::String, ::String) > qjs_bridge_fn;

#ifdef __cplusplus
extern "C" {
#endif

void *qjs_create(void);
void qjs_destroy(void *handle);
int qjs_eval(void *handle, ::String code, ::String filename);
::String qjs_last_error(void *handle);
void qjs_set_number(void *handle, ::String name, double value);
void qjs_set_string(void *handle, ::String name, ::String value);
void qjs_set_bool(void *handle, ::String name, int value);
double qjs_get_number(void *handle, ::String name);
::String qjs_get_string(void *handle, ::String name);
int qjs_has_function(void *handle, ::String name);
::String qjs_call_json(void *handle, ::String name, ::String jsonArgs);
void qjs_set_bridge(qjs_bridge_fn fn);

#ifdef __cplusplus
}
#endif
