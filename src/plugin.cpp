/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <string.h>
#include <obs-module.h>
#include "obs-websocket-api.h"

#if LIBOBS_API_VER != MAKE_SEMANTIC_VERSION(29, 1, 0)
#error "Build with OBS 29.1.0 headers to preserve the minimum supported OBS version."
#endif

OBS_DECLARE_MODULE()

static obs_websocket_vendor vendor;
static bool registered;

MODULE_EXPORT const char *obs_module_description(void)
{
    return "Send a custom DOM event to one named browser source.";
}

static void fail(obs_data_t *response, const char *error)
{
    obs_data_set_bool(response, "ok", false);
    obs_data_set_string(response, "error", error);
}

static void send_event(obs_data_t *request, obs_data_t *response, void *unused)
{
    (void)unused;
    const char *name = obs_data_get_string(request, "sourceName");
    const char *event = obs_data_get_string(request, "eventName");
    if (!*name || !*event) {
        fail(response, "sourceName and eventName are required non-empty strings");
        return;
    }
    if (strlen(name) > 1024 || strlen(event) > 256) {
        fail(response, "Source or event name is too long");
        return;
    }
    obs_data_t *data = obs_data_get_obj(request, "eventData");
    if (!data && obs_data_has_user_value(request, "eventData")) {
        fail(response, "eventData must be a JSON object");
        return;
    }
    const char *json = data ? obs_data_get_json(data) : "{}";
    if (!json || strlen(json) > 65536) {
        if (data) obs_data_release(data);
        fail(response, "eventData exceeds 64 KiB or cannot be serialized");
        return;
    }
    obs_source_t *source = obs_get_source_by_name(name);
    if (!source) {
        if (data) obs_data_release(data);
        fail(response, "Source not found");
        return;
    }
    const char *id = obs_source_get_unversioned_id(source);
    if (!id || strcmp(id, "browser_source") != 0) {
        obs_source_release(source);
        if (data) obs_data_release(data);
        fail(response, "Target is not a browser source");
        return;
    }
    calldata_t args;
    calldata_init(&args);
    calldata_set_string(&args, "eventName", event);
    calldata_set_string(&args, "jsonString", json);
    bool accepted = proc_handler_call(obs_source_get_proc_handler(source),
                                     "javascript_event", &args);
    calldata_free(&args);
    obs_source_release(source);
    if (data) obs_data_release(data);
    if (!accepted) {
        fail(response, "Browser source does not expose javascript_event");
        return;
    }
    obs_data_set_bool(response, "ok", true);
    obs_data_set_string(response, "status", "dispatched_no_delivery_ack");
}

bool obs_module_load(void) { return true; }

void obs_module_post_load(void)
{
    vendor = obs_websocket_register_vendor("targeted-browser-events");
    if (vendor)
        registered = obs_websocket_vendor_register_request(vendor, "emit_event",
                                                           send_event, NULL);
    blog(registered ? LOG_INFO : LOG_ERROR,
         "[targeted-browser-events] %s",
         registered ? "Ready" : "Unable to register obs-websocket request");
}

void obs_module_unload(void)
{
    // OBS may unload obs-websocket first. Its API proc handler and vendors
    // have then already been destroyed, so even unregistering is unsafe.
    // obs-websocket owns the registration and releases it during shutdown.
    // Only clear our local state here; never call another module on unload.
    registered = false;
    vendor = NULL;
    _ph = NULL;
}
