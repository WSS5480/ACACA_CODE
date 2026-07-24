# Ácasa / acasa — Registro de cambios (3000 = Rails backend + páginas estáticas)

> Todo el trabajo se hace en `public/` (admin.html, shop.html) y el backend Rails (puerto 3000).
> NO se toca `www-acasa-main` (el front Next.js en 3001) — se portará después manualmente.
> Cada cambio nuevo se agrega arriba con fecha.

---

## 2026-07-24

### Tienda (shop.html) — precio y buscador
- **Precio en el pop-up = Total = costo × turns** (confirmado como el modelo correcto; un cambio a "solo costo" fue un malentendido y se revirtió).
- **Enganche mínimo unificado a `minDpOf`** (10% del precio de contado = costo × turns × factor) en TODO (openProd, slider, caja escrita). Antes el pop-up usaba 10% del Total, lo que inflaba el enganche y **eliminaba por error el plan de 12 meses** (52 semanas). Ya aparecen los 4 plazos (12/9/6/3 meses) cuando califican (semanal ≥ $25).
- **Buscador de la tienda** ahora exige que **cada palabra** aparezca en título, marca, **modelo**, keywords o categoría (en cualquier orden, sin acentos). Antes solo buscaba en título/marca y como frase exacta, así que buscar por número de modelo o varias palabras no funcionaba.
- Sello de versión: `acasa-shop-2026-07-24-search-v4`.

### Catálogo admin (admin.html)
- Nueva columna **"Modelo"** (model_number) en la tabla de catálogo, ordenable, entre ASIN y Categoría. El dato ya venía en el serializer de la lista (`ProductSerializer`), no hubo cambio de backend.

### Git / respaldo
- Se creó un punto de restauración con TODO el trabajo sin commitear (antes solo estaba el commit del 13-jul). Ahora se hace **commit por cada cambio** (nueva rutina).
- Commits del día: `e250cff` (buscador), `e20af21` (columna Modelo), `5bcada9`/`5ad17fd` (precios), `6f37850` (punto de restauración).
- **Pendiente:** `git push origin main` desde la terminal de Steve — el main local está adelantado sobre GitHub (sin red hacia GitHub desde la sesión).

---

## 2026-07-23 (tarde) — RECONSTRUCCIÓN del modelo de precio en la tienda (shop.html)

El archivo `shop.html` se había revertido a una versión vieja y **se perdió todo el trabajo de precios**. Se reconstruyó EXACTAMENTE al modelo aprobado (extraído del historial + del doc `storefront-display-model`):

- **norm()** ahora mapea `turns` y `decimal_factor` de cada producto (antes no).
- **Helpers de precio** (nuevos): `totalOf(p)=eff(p)×turns`, `cashOf(p)=totalOf×decimal_factor`, `MIN_DP=0.10`, `TERMS=[52,39,26,13]` (=12/9/6/3 meses), `minDpOf(p)=cashOf×10%`, `MIN_WEEKLY=25`, `desdeOf(p)` = semanal más bajo que califica (≥ $25).
- **Tarjeta**: muestra `desde $X / semana` (usa `desdeOf`, ya no `min_weekly_payment`).
- **Pop-up**: "Precio" = **Total** (precio × turns). Enganche con **caja editable `#m-dpnum`** sincronizada con el slider `#m-dp` (piso 10%).
- **Planes** calculados en el navegador: `semanal = (Total − enganche) / semanas`, solo se muestran los ≥ $25 (`renderPlans`). Ya NO llama a `/api/orders/simulate_payment_plans`.
- **W2M** corregido a `{52:12,39:9,26:6,13:3}` (antes tenía 34:8).
- **Solicitud de crédito** ("Solicitar este plan"): el formulario ahora pide vivienda (propia/rentada), meses en EE.UU., meses en domicilio, meses en empleo e ingreso mensual, y hace POST a **`/api/users/client_register`** (antes `/api/signup` con contraseña). Muestra número de cliente + línea de crédito aprobada.
- **Anti-reversión**: se agregó un sello de versión visible (`BUILD acasa-shop-2026-07-23-pricing-v2`) al inicio del HTML y `console.log('[acasa] shop.html build: …')`. Si ese sello NO está en el archivo servido, el archivo se revirtió. Backup guardado en `_changelog/backups/`.

---

## 2026-07-23

### Tienda (shop.html): mostraba solo 200 productos → ahora TODO el catálogo
- shop.html pedía `page=1&per_page=200`. Con 242 productos, los productos #201+ (ej. la motosierra id 243) NO salían en la tienda.
- Ahora pide `page=-1` (todo el catálogo activo), como el admin. La motosierra ya aparece.
- (Diagnóstico hecho abriendo la tienda en el navegador y consultando la API: la motosierra estaba `active`, precio $110.18, con sus 4 categorías — solo quedaba fuera del corte de 200.)

### Filtro: Categoría = 1er nivel, Subcategoría = niveles profundos
- El filtro de categorías usa el breadcrumb real: **Categoría = primer nivel** (ej. "Electrónicos", "Jardín"); **Subcategoría = niveles más profundos** (ej. "Motosierras").
- (Se probó una versión "plana" que mezclaba niveles; se revirtió a la jerarquía.)

### Filtros del catálogo ahora reflejan el catálogo REAL (admin.html + shop.html)
- Los dropdowns de filtro (Categoría / Subcategoría) ya NO usan el árbol curado (RFTREE).
- Ahora se construyen desde las **categorías reales de Amazon** de cada producto (breadcrumb guardado al importar).
  - Categoría = 1er nivel del breadcrumb (ej. "Jardín", "Electrónicos").
  - Subcategoría = niveles más profundos (ej. "Motosierras", "Televisiones").
- Ejemplo: una motosierra (Amazon: "Jardín → … → Motosierras") ahora sale al filtrar Categoría "Jardín" → Subcategoría "Motosierras". Antes no aparecía porque el árbol curado la ponía en "Herramientas".
- El scraper SIGUE usando el árbol curado (RFTREE) para BUSCAR en Amazon — eso no cambió.

### Scraper / Importador de Amazon (admin.html — SOLO admin)
- Búsqueda por palabra clave con rango de precio (Rainforest `search`, filtrado por precio del lado del servidor).
- Dropdowns en cascada del scraper: **Categoría** (= departamento) → **Subcategoría** (hoja). Con opción "Categoría"/"Subcategoría" como default.
- Checkbox **"Más vendidos de Amazon"**: al activarlo aparece (junto al checkbox) el dropdown **"Categoría (Amazon MX)"** con categorías reales de Rainforest; oculto si no está activo.
- Insignias por producto: **Sold ✓/✗** y **Delivered ✓/✗** (verde = Amazon, rojo = no, gris = sin verificar).
- Botón único en **2 pasos**: "Verificar y descargar" → 1er clic verifica (solo lo seleccionado; si no hay selección, todo), 2º clic descarga lo seleccionado. No se puede descargar sin verificar.
- Barra de progreso: animada al scrapear, se llena por-producto al verificar y al descargar.
- Verificación: solo cobra créditos por productos NUEVOS (caché en el navegador por ASIN, sobrevive refresh). Al descargar reutiliza el detalle (caché Redis) → no recobra crédito.
- Tras verificar seleccionados: la vista/caché deja SOLO esos productos.
- Productos ya en el catálogo: tachados en rojo ("Ya en catálogo"), no seleccionables.
- Filtro "Vendido/Entregado por Amazon" quitado (redundante con las insignias).
- Botón "Limpiar resultados".

### Catálogo (admin.html)
- Filtro superior en cascada de **2 dropdowns**: Categoría (= departamento) → Subcategoría, podado a lo que existe en el catálogo.
- Columna **Foto** con miniatura (zoom al pasar el mouse) + insignias Sold/Del bajo la foto.
- Insignia roja "⚠ Ya no está en Amazon" + botón "Verificar en Amazon (sin créditos)" (consulta la página real, sin Rainforest).
- Fila de filtros por columna ("filtrar…") eliminada.
- Borrar/editar productos, eliminar por selección o filtro.

### Tienda (shop.html)
- Pills de categoría reemplazadas por los mismos **2 dropdowns**: Categoría → Subcategoría, podados al catálogo.

### Marca
- "Ácasa"/"ácasa" → **acasa** (minúscula, sin acento) en todas las páginas y correos. (Identificadores de código `AcasaApi` y `ACASA_API_*` NO se tocan.)

### Backend
- Endpoints nuevos: `rainforest_search`, `check_sellers`, `verify_availability`.
- Caché Redis del detalle de producto (6 h) para no recobrar créditos entre verificar y descargar.
- Productos importados quedan etiquetados con su subcategoría (`keywords`) para el filtro del catálogo.

---

## Pendiente / por portar a 3001 (después)
- Filtro del catálogo (2 dropdowns Categoría/Subcategoría) — ya hecho en 3000 (admin + shop), falta portar a productos.js.
- (El scraper es solo admin — NO se porta a 3001.)
