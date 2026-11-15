#include "qjs_glue.h"

#include <string>
#include <cstring>
#include <vector>

/* Opaque per-script QuickJS instance. */
struct QjsHandle
{
	JSRuntime *rt;
	JSContext *ctx;
	std::string err;
	std::string scratch;
};

static qjs_bridge_fn g_bridge;
static bool g_bridgeSet = false;

static const char *cstr(const ::String &s)
{
	return s.raw_ptr() ? s.utf8_str() : "";
}

static ::String makeString(const std::string &s)
{
	return ::String::create(s.c_str());
}

static void storeException(QjsHandle *h, const char *fallback)
{
	JSValue ex = JS_GetException(h->ctx);
	const char *p = JS_ToCString(h->ctx, ex);
	h->err = (p != NULL) ? p : (fallback != NULL ? fallback : "unknown QuickJS error");
	if (p != NULL) JS_FreeCString(h->ctx, p);
	JS_FreeValue(h->ctx, ex);
}

/* Single JS->Haxe entry point. JS prelude wraps it into named engine functions. */
static JSValue js_hx(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv)
{
	const char *name = (argc > 0) ? JS_ToCString(ctx, argv[0]) : NULL;
	const char *json = (argc > 1) ? JS_ToCString(ctx, argv[1]) : NULL;
	if (name == NULL || json == NULL)
	{
		if (name != NULL) JS_FreeCString(ctx, name);
		if (json != NULL) JS_FreeCString(ctx, json);
		return JS_EXCEPTION;
	}

	::String result;
	if (g_bridgeSet)
		result = g_bridge(::String::create(name), ::String::create(json));

	JS_FreeCString(ctx, name);
	JS_FreeCString(ctx, json);

	const char *p = result.raw_ptr() ? result.utf8_str() : "";
	return JS_NewString(ctx, p != NULL ? p : "");
}

static JSValue globalObject(JSContext *ctx)
{
	return JS_GetGlobalObject(ctx);
}

void *qjs_create(void)
{
	QjsHandle *h = new QjsHandle();
	h->rt = NULL;
	h->ctx = NULL;

	h->rt = JS_NewRuntime();
	if (h->rt == NULL)
	{
		h->err = "JS_NewRuntime failed";
		return h;
	}
	h->ctx = JS_NewContext(h->rt);
	if (h->ctx == NULL)
	{
		h->err = "JS_NewContext failed";
		return h;
	}

	JSValue global = globalObject(h->ctx);
	JSValue fn = JS_NewCFunction(h->ctx, js_hx, "__hx", 2);
	JS_SetPropertyStr(h->ctx, global, "__hx", fn); /* takes ownership of fn */
	JS_FreeValue(h->ctx, global);

	return h;
}

void qjs_destroy(void *handle)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL) return;
	if (h->ctx != NULL) JS_FreeContext(h->ctx);
	if (h->rt != NULL) JS_FreeRuntime(h->rt);
	delete h;
}

int qjs_eval(void *handle, ::String code, ::String filename)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL || h->ctx == NULL) return -1;
	h->err.clear();

	const char *src = cstr(code);
	const char *file = cstr(filename);
	JSValue ret = JS_Eval(h->ctx, src, strlen(src), (file[0] != 0) ? file : "<js>", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(ret))
	{
		storeException(h, "JS_Eval failed");
		JS_FreeValue(h->ctx, ret);
		return 1;
	}
	JS_FreeValue(h->ctx, ret);
	return 0;
}

::String qjs_last_error(void *handle)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL) return ::String::create("null handle");
	return makeString(h->err);
}

static JSValue globalOf(QjsHandle *h)
{
	return globalObject(h->ctx);
}

void qjs_set_number(void *handle, ::String name, double value)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL || h->ctx == NULL) return;
	JSValue global = globalOf(h);
	JS_SetPropertyStr(h->ctx, global, cstr(name), JS_NewFloat64(h->ctx, value));
	JS_FreeValue(h->ctx, global);
}

void qjs_set_string(void *handle, ::String name, ::String value)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL || h->ctx == NULL) return;
	JSValue global = globalOf(h);
	JS_SetPropertyStr(h->ctx, global, cstr(name), JS_NewString(h->ctx, cstr(value)));
	JS_FreeValue(h->ctx, global);
}

void qjs_set_bool(void *handle, ::String name, int value)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL || h->ctx == NULL) return;
	JSValue global = globalOf(h);
	JS_SetPropertyStr(h->ctx, global, cstr(name), JS_NewBool(h->ctx, value ? 1 : 0));
	JS_FreeValue(h->ctx, global);
}

double qjs_get_number(void *handle, ::String name)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL || h->ctx == NULL) return 0.0;
	JSValue global = globalOf(h);
	JSValue v = JS_GetPropertyStr(h->ctx, global, cstr(name));
	double out = 0.0;
	if (!JS_IsUndefined(v)) JS_ToFloat64(h->ctx, &out, v);
	JS_FreeValue(h->ctx, v);
	JS_FreeValue(h->ctx, global);
	return out;
}

::String qjs_get_string(void *handle, ::String name)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL || h->ctx == NULL) return ::String::create("");
	JSValue global = globalOf(h);
	JSValue v = JS_GetPropertyStr(h->ctx, global, cstr(name));
	if (JS_IsUndefined(v) || JS_IsNull(v))
	{
		JS_FreeValue(h->ctx, v);
		JS_FreeValue(h->ctx, global);
		return ::String::create("");
	}
	const char *p = JS_ToCString(h->ctx, v);
	h->scratch = (p != NULL) ? p : "";
	if (p != NULL) JS_FreeCString(h->ctx, p);
	JS_FreeValue(h->ctx, v);
	JS_FreeValue(h->ctx, global);
	return makeString(h->scratch);
}

int qjs_has_function(void *handle, ::String name)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL || h->ctx == NULL) return 0;
	JSValue global = globalOf(h);
	JSValue v = JS_GetPropertyStr(h->ctx, global, cstr(name));
	int ok = JS_IsFunction(h->ctx, v) ? 1 : 0;
	JS_FreeValue(h->ctx, v);
	JS_FreeValue(h->ctx, global);
	return ok;
}

::String qjs_call_json(void *handle, ::String name, ::String jsonArgs)
{
	QjsHandle *h = (QjsHandle *)handle;
	if (h == NULL || h->ctx == NULL) return ::String::create("");
	h->err.clear();

	JSValue global = globalOf(h);
	JSValue fn = JS_GetPropertyStr(h->ctx, global, cstr(name));
	if (!JS_IsFunction(h->ctx, fn))
	{
		JS_FreeValue(h->ctx, fn);
		JS_FreeValue(h->ctx, global);
		h->err = "not a function";
		return ::String::create("");
	}

	const char *args = cstr(jsonArgs);
	if (args[0] == 0) args = "[]";
	JSValue parsed = JS_ParseJSON(h->ctx, args, strlen(args), "<args>");
	int argc = 0;
	std::vector<JSValue> argv;
	if (!JS_IsException(parsed))
	{
		JSValue lenVal = JS_GetPropertyStr(h->ctx, parsed, "length");
		uint32_t len = 0;
		if (JS_ToUint32(h->ctx, &len, lenVal) == 0 && len > 0 && len <= 64)
		{
			argc = (int)len;
			argv.resize(len);
			for (uint32_t i = 0; i < len; i++)
				argv[i] = JS_GetPropertyUint32(h->ctx, parsed, i);
		}
		JS_FreeValue(h->ctx, lenVal);
	}
	else
	{
		storeException(h, "invalid JSON arguments");
	}

	JSValue ret = JS_Call(h->ctx, fn, JS_UNDEFINED, argc, argc > 0 ? &argv[0] : NULL);
	for (int i = 0; i < argc; i++) JS_FreeValue(h->ctx, argv[i]);
	JS_FreeValue(h->ctx, parsed);
	JS_FreeValue(h->ctx, fn);
	JS_FreeValue(h->ctx, global);

	if (JS_IsException(ret))
	{
		storeException(h, "JS_Call failed");
		JS_FreeValue(h->ctx, ret);
		return ::String::create("");
	}

	JSValue json = JS_JSONStringify(h->ctx, ret, JS_UNDEFINED, JS_UNDEFINED);
	JS_FreeValue(h->ctx, ret);
	if (JS_IsException(json))
	{
		storeException(h, "JSON stringify failed");
		JS_FreeValue(h->ctx, json);
		return ::String::create("");
	}
	const char *p = JS_ToCString(h->ctx, json);
	h->scratch = (p != NULL) ? p : "";
	if (p != NULL) JS_FreeCString(h->ctx, p);
	JS_FreeValue(h->ctx, json);
	return makeString(h->scratch);
}

void qjs_set_bridge(qjs_bridge_fn fn)
{
	g_bridge = fn;
	g_bridgeSet = true;
}
