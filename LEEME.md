# OBS Targeted Events — 0.1.2 experimental

La versión 0.1.2 corrige un fallo al cerrar OBS: el plugin intentaba cancelar su
registro después de que obs-websocket destruyera su API. Ahora deja esa limpieza
al propietario del registro, obs-websocket. El mínimo sigue siendo OBS 29.1.0.
Con OBS cerrado, sustituye la DLL anterior por la nueva compilación.

Plugin nativo compilado en Windows x64, configuración Release, con MSVC 19.29
(Visual Studio Build Tools 2019) y cabeceras y biblioteca de importación de OBS 29.1.0.
La DLL generada está en `package/obs-plugins/64bit/obs-targeted-events.dll`.
La prueba de integración en OBS descrita abajo sigue pendiente antes de usarlo en directo.

Envía un evento DOM únicamente a la fuente de navegador indicada por su nombre exacto.
No modifica obs-browser y no necesita servidor adicional. Usa el servidor WebSocket
de OBS y su autenticación habitual. El evento se recibe en event.detail.

## Compatibilidad mínima

**OBS Studio 29.1.0 o posterior, Windows x64**, con obs-browser y obs-websocket
5.2 o posterior cargados. OBS 29.1.0 ya incluye ambos componentes necesarios.
La DLL declara la API 29.1.0; no requiere OBS 32.2 para cargarse.

OBS 29.0.x y anteriores no incluyen el procedimiento por fuente `javascript_event`
que usa este plugin. El cambio oficial está en:
https://github.com/obsproject/obs-browser/commit/501f624e0eabe851358bcc34dca785bbf52ac1c9
La revisión de obs-browser incluida en OBS 29.1.0 puede consultarse en:
https://github.com/obsproject/obs-studio/tree/29.1.0/plugins/obs-browser

Se han comprobado la carga de la DLL, sus imports y exports, y su versión de API
contra los runtimes oficiales de OBS **29.1.0** y **32.2.2**, en procesos separados.
Estas comprobaciones no inician OBS ni demuestran la entrega del evento al HTML;
la prueba de aislamiento descrita abajo sigue pendiente.

## Compilar para Windows x64

### Compilación automática con mínimo OBS 29.1.0

Ejecuta desde esta carpeta:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows.ps1
```

Requiere CMake >=3.24 y Visual Studio con herramientas C++ (2019 16.11 o posterior).
El script descarga las fuentes oficiales y el paquete portátil de OBS 29.1.0,
usa el header oficial de obs-websocket 5.2 de esa versión y verifica sus SHA-256.
Prepara en `.deps` las cabeceras y una biblioteca de importación a partir de los
exports del `obs.dll` **de OBS 29.1.0**. Compila en C++17 porque ese header oficial
usa características de ese estándar. No es necesario compilar todo OBS.

El paquete portátil queda aislado en `.deps`: no se instala ni se ejecuta, y
no modifica tu instalación habitual de OBS. Esta puede ser 29.1 o una posterior;
ni siquiera es necesario tener OBS instalado para compilar.

Por defecto usa CMake en `C:\Program Files\CMake\bin\cmake.exe`, ajustable con
`-CMakePath`. Opcionalmente, `-OBSInstallDir` permite seleccionar un paquete
**29.1.0 x64** ya extraído para enlazar, evitando descargar el paquete portátil.
No indica dónde instalar la DLL resultante. Solo la primera descarga requiere Internet.
El resultado queda en `package/obs-plugins/64bit/obs-targeted-events.dll`.

### Compilación con un SDK externo

Requisitos: Visual Studio con Desarrollo de escritorio con C++, CMake >=3.24,
SDK/libobs de desarrollo x64 **29.1.0** (headers, obs.lib y
libobsConfig.cmake), y el header oficial obs-websocket-api.h.
La instalación normal de OBS por sí sola NO constituye un SDK de desarrollo.
Si no dispones de SDK, hay que preparar/compilar libobs siguiendo las instrucciones
de compilación de OBS para Windows: https://github.com/obsproject/obs-studio/wiki

Usa el header oficial fijado en `vendor/obs-websocket-api.h`, conservando su
licencia. CMake exige el SDK 29.1.0 exacto y el código comprueba su versión para
evitar elevar el mínimo por accidente al compilar con un SDK reciente.

Desde PowerShell en esta carpeta, ajusta la ruta del SDK:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_PREFIX_PATH="C:/ruta/al/sdk-obs-29.1.0" -DOBS_WEBSOCKET_INCLUDE_DIR="$PWD/vendor"
cmake --build build --config Release
cmake --install build --config Release --prefix "$PWD/package"
```

Cierra OBS. Copia package/obs-plugins/64bit/obs-targeted-events.dll a
obs-plugins/64bit dentro de tu instalación de OBS (junto a los otros plugins).
Reabre OBS y comprueba en el registro: [targeted-browser-events] Ready.
Para desinstalar, cierra OBS y elimina únicamente obs-targeted-events.dll.
Si tenías la DLL anterior compilada contra 32.2.2, sustitúyela por la nueva.

### Comprobar la compatibilidad binaria

Con Python de 64 bits, ejecuta cada comprobación en un proceso separado:

```powershell
python scripts/check-windows-compatibility.py .deps/obs-runtime-29.1.0 package/obs-plugins/64bit/obs-targeted-events.dll
python scripts/check-windows-compatibility.py "C:\Program Files\obs-studio" package/obs-plugins/64bit/obs-targeted-events.dll
```

El script comprueba carga de dependencias, exports del módulo y API 29.1.0.
La segunda orden prueba el OBS de la ruta indicada. No sustituye la prueba de
entrega al navegador dentro de OBS.

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
API de WebSocket: https://github.com/obsproject/obs-websocket/blob/6ef055a369249f6d7b008914fe2bc360c96f23dc/lib/obs-websocket-api.h
Procedimiento javascript_event en OBS 29.1.0: https://github.com/obsproject/obs-browser/blob/594115a27d40f0916e55db97cb61f7c7130cbe28/obs-browser-source.cpp
