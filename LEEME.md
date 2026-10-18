# OBS Targeted Events — 0.1.0 experimental

Plugin nativo compilado en Windows x64, configuración Release, con MSVC 19.29
(Visual Studio Build Tools 2019) y cabeceras oficiales de OBS 32.2.2.
La DLL generada está en `package/obs-plugins/64bit/obs-targeted-events.dll`.
La prueba de integración en OBS descrita abajo sigue pendiente antes de usarlo en directo.

Envía un evento DOM únicamente a la fuente de navegador indicada por su nombre exacto.
No modifica obs-browser y no necesita servidor adicional. Usa el servidor WebSocket
de OBS y su autenticación habitual. El evento se recibe en event.detail.

## Compilar para Windows x64

### Compilación automática para OBS 32.2.2 instalado

Ejecuta desde esta carpeta:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows.ps1
```

El script detecta Visual Studio con herramientas C++ (2019 16.11 o posterior),
descarga las fuentes oficiales de OBS 32.2.2 y el header de obs-websocket fijado
al commit de esa versión, y verifica sus SHA-256. Prepara en `.deps` las cabeceras
y una biblioteca de importación a partir de los exports del `obs.dll` instalado.
El plugin enlaza con ese OBS; no es necesario compilar todo OBS ni instalar otro IDE.
Este SDK local está preparado para este plugin C x64 y esta versión de OBS.

Por defecto usa OBS en `C:\Program Files\obs-studio` y CMake en
`C:\Program Files\CMake\bin\cmake.exe`. Se pueden ajustar con los parámetros
`-OBSInstallDir` y `-CMakePath`. Solo la primera descarga requiere Internet.
El resultado queda en `package/obs-plugins/64bit/obs-targeted-events.dll`.

### Compilación con un SDK externo

Requisitos: Visual Studio con Desarrollo de escritorio con C++, CMake >=3.24,
SDK/libobs de desarrollo x64 compatible con tu versión de OBS (headers, obs.lib y
libobsConfig.cmake), y el header oficial obs-websocket-api.h.
La instalación normal de OBS por sí sola NO constituye un SDK de desarrollo.
Si no dispones de SDK, hay que preparar/compilar libobs siguiendo las instrucciones
de compilación de OBS para Windows: https://github.com/obsproject/obs-studio/wiki

Descarga el header oficial de:
https://github.com/obsproject/obs-websocket/blob/master/lib/obs-websocket-api.h
Guárdalo en una carpeta vendor conservando su licencia.

Desde PowerShell en esta carpeta, ajusta la ruta del SDK:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_PREFIX_PATH="C:/ruta/al/sdk-obs" -DOBS_WEBSOCKET_INCLUDE_DIR="$PWD/vendor"
cmake --build build --config Release
cmake --install build --config Release --prefix "$PWD/package"
```

Cierra OBS. Copia package/obs-plugins/64bit/obs-targeted-events.dll a
obs-plugins/64bit dentro de tu instalación de OBS (junto a los otros plugins).
Reabre OBS y comprueba en el registro: [targeted-browser-events] Ready.
Para desinstalar, cierra OBS y elimina únicamente obs-targeted-events.dll.

## Enviar desde cualquier cliente OBS WebSocket v5

Conecta y autentica el cliente como de costumbre. Ejecuta la petición
CallVendorRequest usando examples/request.json como sus datos.
No uses el vendor obs-browser: el nuevo vendor es targeted-browser-events.

Con una instancia ya conectada de obs-websocket-js:

```js
const response = await obs.call('CallVendorRequest', {
  vendorName: 'targeted-browser-events',
  requestType: 'emit_event',
  requestData: {
    sourceName: 'Avatar',
    eventName: 'avatar_evento',
    eventData: { accion: 'saltar' }
  }
});
if (!response.responseData?.ok) {
  throw new Error(response.responseData?.error || 'Fallo del plugin');
}
```

El estado exitoso exterior de CallVendorRequest NO significa éxito de entrega:
comprueba responseData.ok. Incluso ok=true solo confirma la llamada al procedimiento
de la fuente; no confirma que el HTML esté cargado ni que haya ejecutado un listener.
No hay cola, reintentos ni confirmación desde JavaScript.

## Prueba de aislamiento en OBS (pendiente de ejecutar)

1. Crea DOS fuentes de navegador distintas, Avatar y Control, cargando overlay.html.
   Usa Crear nueva en ambas: no reutilices la misma fuente existente.
2. Muestra ambas para que sus páginas estén cargadas. Espera a ver sus contadores.
3. Envía el ejemplo: solo Avatar debe subir a 1; Control debe seguir en 0.
4. Cambia sourceName a Control: solo Control debe subir a 1.
5. Prueba un nombre inexistente y una fuente de texto: responseData.ok debe ser false.
6. Prueba eventName vacío y eventData como cadena: deben devolver error.
7. Cierra/reabre OBS y repite la prueba.

Las fuentes apagadas por la opción de cerrar el navegador cuando no es visible
no reciben eventos mientras están descargadas. Espera a que la página cargue.
Si reutilizas una misma fuente en varias escenas, esas apariciones comparten
el mismo navegador: el destino es la fuente, no una aparición de ella en una escena.
eventData admite un objeto JSON, máximo 64 KiB serializado.

## Fundamento y licencia

Código propio: GPL-2.0-or-later. Header externo: licencia original del proyecto.
API de WebSocket: https://github.com/obsproject/obs-websocket/blob/master/lib/obs-websocket-api.h
Procedimiento javascript_event: https://github.com/obsproject/obs-browser/blob/master/obs-browser-source.cpp
