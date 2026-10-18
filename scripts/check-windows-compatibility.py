"""Load the plugin against one OBS runtime and check its declared ABI.

Run once per runtime in separate processes. This checks import resolution and
version exports only; it does not initialize OBS or test browser event delivery.
"""

import argparse
import ctypes
import json
import os
from pathlib import Path


def version_text(value):
    return f"{value >> 24}.{(value >> 16) & 255}.{value & 65535}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("obs_directory", type=Path)
    parser.add_argument("plugin", type=Path)
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("This check requires Windows.")
    if ctypes.sizeof(ctypes.c_void_p) != 8:
        parser.error("Use a 64-bit Python interpreter.")

    obs_bin = args.obs_directory.resolve() / "bin" / "64bit"
    plugin_path = args.plugin.resolve(strict=True)
    with os.add_dll_directory(str(obs_bin)):
        obs = ctypes.WinDLL(str(obs_bin / "obs.dll"))
        plugin = ctypes.WinDLL(str(plugin_path))
        obs.obs_get_version.restype = ctypes.c_uint32
        plugin.obs_module_ver.restype = ctypes.c_uint32
        runtime_version = obs.obs_get_version()
        module_version = plugin.obs_module_ver()
        if module_version != (29 << 24 | 1 << 16):
            raise RuntimeError(f"Unexpected module ABI: {version_text(module_version)}")
        if module_version > runtime_version:
            raise RuntimeError("The OBS runtime is older than the plugin ABI.")
        for name in ("obs_module_load", "obs_module_post_load", "obs_module_unload",
                     "obs_module_set_pointer", "obs_module_description"):
            getattr(plugin, name)

        print(json.dumps({
            "runtime": version_text(runtime_version),
            "plugin_api": version_text(module_version),
            "imports_and_module_exports": "ok",
            "browser_event_delivery": "not tested",
        }))


if __name__ == "__main__":
    main()
