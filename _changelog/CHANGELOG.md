# acasa — Registro de cambios (backend Rails + back office + tienda)

> Cubre los DOS repos: `ACACA_CODE` (API Rails, `public/admin.html`, `public/shop.html`)
> y `www-acasa-main` (la tienda en Next.js, que desde agosto SÍ se trabaja aquí —
> la nota vieja decía que no se tocaba y dejó de ser cierta).
> Cada cambio nuevo se agrega ARRIBA con su fecha **y con su etiqueta de fork**
> ([CORE] / [MX] / [ADAPTAR]) para poder portarlo a BuddyRents sin releer todo.
> La marca se escribe **acasa** (minúscula, sin acento).

---

## Resumen por tema (24-jul-2026 → 19-sep-2026)

> Lectura rápida de lo que cambió en estos dos meses. El detalle commit por commit
> viene abajo. El registro se había quedado en el 24-jul, así que esto cubre todo
> lo que se hizo desde entonces — incluido el fork de RTO (`docs/FORK-BUDDYRENTS.md`,
> 27-ago) y todo lo posterior.

### Dinero y contratos
- **El código ya cobra como dice el contrato**: interés sobre SALDO INSOLUTO
  (cláusula SÉPTIMA, tasa anual ÷ 360 × días), en lugar del factor plano ×1.25.
  Tienda, alta de contratos y carátula cotizan con la misma fórmula (`3c1a0117`).
- **Abono a saldo re-amortiza de verdad**: el extra paga capital y acorta el plazo;
  antes se perdonaba un 25% plano que regalaba de más (`7841bc9c`).
- **Contabilidad completa**: libro append-only por categorías, cortes diario y
  mensual, gastos y P&L, reembolsos y contracargos, comisión de Stripe y FX por
  pago, paquete mensual al contador, recibos imprimibles (`21fe4ed0` y siguientes).
- **Dos palancas de riesgo, apagadas por defecto**: enganche mínimo por categoría
  y tope de pago/ingreso (PTI) (`6c260670`).

### Riesgo
- **Gate de referencias en modo sombra + motor de decisión**: veredicto por
  contrato, reglas juzgadas con estadística real y recomendación
  ENCENDER/AJUSTAR/ESPERAR; nada bloquea al cliente todavía (`6a9db9ff`).
- El motor **ignora los datos de prueba** desde una fecha de corte (`0f1a2fb1`).

### Cobro
- **Stripe México además de Stripe EE. UU.**: el cliente elige pagar en dólares o
  en pesos, con el tipo de cambio del día más margen; tarjetas y autopago por
  moneda; conciliación de depósitos de las dos cuentas (`01bf16c7`, `7b1b1e972`).
- Tarjetas guardadas sin duplicados, autopago y cobro a un clic (`9f9c38e4`, `0d0bce5e`).

### Bancos
- **Cuentas bancarias en el back office**: Plaid (EE. UU.), cuentas manuales con
  importación de estado de cuenta, saldos, movimientos y conciliación contra los
  depósitos de Stripe (`1bb33510`). Plaid quedó verificado en sandbox; falta pasar
  a producción.

### Catálogo y scraper
- **Las categorías son las de Amazon, en todo**: el scraper baja por el árbol real
  (Videojuegos → PlayStation 5 → Accesorios), cada modo pide el catálogo que le
  toca, y la tienda agrupa por la ruta real del producto en vez de una lista
  escrita a mano (`a281f63d`, `f975178e7`, `4fce8ec9`).
- **Promociones de punta a punta**: la oferta se detecta del detalle que manda
  Amazon al descargar, vista 0-6 y orden en el catálogo, y un refresco automático
  (promos a diario, catálogo completo los domingos) que devuelve a precio normal
  lo que ya no está en oferta (`0183a591`, `7544b1b3`).
- **Columna Ventas** con desglose 30/60/90 y filtro para encontrar lo que no se
  vende y poder borrarlo (`f0de8386`).
- **Rendimiento**: la tienda tardaba 7-8 s en abrir el catálogo por miles de
  consultas repetidas; ahora son 2.2-2.6 s (`48fcc372`).

### Operación y seguridad
- **Switch de Go Live**: borra los datos transaccionales de prueba en un paso y
  conserva toda la configuración, con respaldo obligatorio antes (`85a2ca79`).
- **Migraciones garantizadas en cada deploy** (tercer intento, el definitivo):
  se aplican dentro del propio proceso al arrancar (`d9914ccd`).
- **Verificación por WhatsApp obligatoria** para iniciar sesión (`e975a9cb`).
- **Compradores en cualquier país**: país de residencia, husos horarios, teléfonos
  internacionales y países atendidos configurables (`680f8e64`).
- Contraseñas de 8 caracteres mínimo, por la política de seguridad (`7ae803a7`).
- **Política de Seguridad de la Información** de Otthon Group USA, LLC escrita
  para el cuestionario de Plaid (documento entregado aparte, no vive en el repo).

---

## Pendientes (lo que falta, para no perderlo de vista)

**Llaves y configuración**
- `STRIPE_PUBLISHABLE_KEY` en Render y `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` en Vercel.
- Stripe México: `STRIPE_MX_SECRET_KEY`, `STRIPE_MX_PUBLISHABLE_KEY`,
  `STRIPE_MX_WEBHOOK_SECRET` en Render; webhook
  `https://acasa-web.onrender.com/api/stripe/webhook` con `payment_intent.succeeded`
  en el panel de Stripe México. Opcional: `FX_MARKUP_PCT`.
- Plaid a producción: pedir acceso, desconectar la conexión de sandbox y cambiar
  `PLAID_SECRET` / `PLAID_ENV`.

**Al lanzar**
- Quitar la insignia de versión (arriba a la izquierda de la tienda).
- Quitar el botón de borrado real de renglones del libro (marcado en código, `ee682c6c`).

**Seguridad / infraestructura**
- MFA en las 9 cuentas listadas.
- Dependabot en los dos repos.
- Respaldo semanal de la base a S3 + prueba de restauración dos veces al año
  (comprometido en la política de seguridad).
- Hacer privado el repo de GitHub.
- `.gitignore`: `.21st/`, `.claude/`, `.codex/`, `.cursor/`, `Claude outputs/`,
  `_backup/`, `_changelog/backups/`, `_to_delete/`, `tmp_stage2/`, y los archivos
  sueltos `cd` y `git` (de comandos mal tecleados).

**Abogado**
- Cobrar en pesos a clientes mexicanos sobre un contrato en dólares (junto a la
  cláusula BBVA/Stripe USD).
- Cláusula 23, San Antonio.
- Carátula con dirección internacional.
- Aviso de privacidad LFPDPPP y la grafía "Ácasa".
- Países, AML/KYC y firma electrónica desde el extranjero.

**Decisión de negocio pendiente**
- Pagos anticipados parciales (`apply_payment_saldo!`) sigue con la rebaja del
  modelo viejo; requiere re-amortización. Los contratos ya emitidos conservan su
  tabla plana salvo que se regeneren (`3c1a0117`).

---

## Qué se lleva al fork de RTO (BuddyRents) y qué NO

> Este registro existe para poder **portar los cambios al fork de RTO** sin volver
> a leer 490 commits. La regla no es inventada: sale de `docs/FORK-BUDDYRENTS.md`
> — Paso 1 (lo que se BORRA en el modelo doméstico de EE. UU.) y la nota de
> *Shared-fix discipline*, que dice que **contabilidad, crédito, scraper y admin
> son 90% código común**.

Cada renglón del registro de abajo lleva una etiqueta:

| Etiqueta | Qué significa |
|---|---|
| **[CORE]** | Núcleo común. Se cherry-pickea tal cual al fork. |
| **[MX]** | Maquinaria transfronteriza o de México. **NO va** al fork doméstico. |
| **[ADAPTAR]** | Sí se lleva, pero hay que reescribir algo (idioma, marca, texto legal, WhatsApp, fotos). |
| **[REVISAR]** | No se pudo clasificar solo por el título del commit. Necesita un ojo humano. |

### [MX] — lo que NO pertenece al fork
Es justamente el pago de hacerlo doméstico: se borra, no se rebrandea.
- **Tipo de cambio y pesos**: `ExchangeRate`, `FxReprice`, la repreciación diaria,
  la semántica de `original_price` en MXN. En EE. UU. el precio es solo USD.
- **Stripe México y el cobro en pesos**: la elección de moneda, el margen de FX y
  las tarjetas por moneda. El fork cobra en dólares y punto.
- **Quien recibe en México** (beneficiario) y el parentesco asociado.
- **País de entrega** (aquí ya es siempre México → en el fork el campo desaparece).
- **Compradores en cualquier país / husos horarios / teléfonos internacionales**:
  eso resuelve un problema que el modelo doméstico no tiene.
- **IVA** → en EE. UU. es sales tax por estado, otra semántica.
- **Aviso de privacidad LFPDPPP** y el contrato mexicano.

### [ADAPTAR] — se lleva, pero se reescribe
- **Texto legal**: el contrato y las carátulas. ⚠ El rent-to-own en EE. UU. está
  regulado por estado (avisos obligatorios, topes de precio en algunos). El
  playbook es explícito: **no portar el contrato mexicano, pedirlo al abogado.**
- **WhatsApp**: el mecanismo (verificación, plantillas, alertas) sirve igual; el
  número, el idioma y las plantillas aprobadas son otras.
- **Correos y recibos**: la mecánica es común; el logo, el remitente y los textos cambian.
- **Landing, fotos y colores**: la flecha de neón está horneada en las imágenes —
  hay que fotografiar y componer de nuevo.
- **Idioma**: todo el front y el admin están en español.

### [CORE] — lo que se cherry-pickea tal cual
Lo más valioso de estos dos meses cae aquí:
- **Motor de crédito**: interés sobre saldo insoluto, re-amortización del abono a
  saldo, planes por plazo. La matemática no depende del país.
- **Contabilidad**: libro append-only, cortes, gastos y P&L, reembolsos y
  contracargos, paquete al contador.
- **Motor de riesgo**: gate de referencias en sombra y el motor de decisión
  (la regla de *cuántas* referencias sí cambia — ver [ADAPTAR]).
- **Scraper**: ya trae selector de mercado (Amazon MX / Amazon EE. UU.), así que
  el árbol real de categorías, las subcategorías, promociones y la verificación de
  vendedor/foto funcionan igual apuntando a `amazon.com`.
- **Catálogo del admin**: vistas 0-6 y orden, columnas plegables, columna Ventas y
  el filtro de lo que no se vende, aplicar al grupo.
- **Rendimiento**: la caché de configuración por petición y las precargas.
- **Infraestructura**: migraciones garantizadas al desplegar, switch de Go Live,
  política de contraseñas, bitácora.
- **Bancos**: Plaid es de EE. UU. — en el fork aplica igual o mejor.

> **Aviso honesto sobre las etiquetas**: las de la lista de abajo son un primer
> pase automático, hecho con palabras clave sobre el título del commit. Están para
> ahorrar trabajo, no para decidir sola. Todo lo que quedó **[REVISAR]** hay que
> verlo a mano, y cualquier etiqueta se puede corregir — es un archivo de texto.

---

## 2026-07-24 -> 2026-09-19 - Registro recuperado del historial de git

> Generado LEYENDO git (no de memoria): 259 commits del backend/admin y 231 de
> la tienda. Cada renglon trae su commit (`git show <hash>`) y su etiqueta de
> fork (ver la seccion de arriba).
>
> Reparto de las 490 etiquetas: **CORE 146** - **MX 43** - **ADAPTAR 188** - **REVISAR 113**.

### 2026-09-18

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `f0de8386` Catalogo: columna Ventas (pedidos no cancelados) con desglose de 30/60/90 dias y ultima venta al pasar el mouse, y filtro para encontrar lo que no se vende (nunca / sin ventas en 30, 60 o 90 dias) y poder seleccionarlo y borrarlo. Las ventas salen de UNA sola consulta agrupada y solo cuando el admin las pide, asi que la tienda no se hace mas lenta
- **[CORE]** `c9eddea3` Promociones con la marca: al cliente se le dice Promocion de acasa en vez de la etiqueta de Amazon (esa se queda solo para el equipo en el admin), y la insignia del catalogo dice PROMOCION DE ACASA
- **[CORE]** `e84e8816` Scraper: el aviso de 'ya en catalogo' tapaba la casilla de seleccion en las tarjetas de promociones, asi que no se veia que estaba seleccionado y no se podian re-descargar; ahora va dentro de la tarjeta y la casilla es mas grande y visible
- **[CORE]** `7544b1b3` La promocion se decide al descargar con el detalle que Amazon ya mando (precio de lista contra precio de venta) y no con lo que traia la pantalla: ahora queda marcada venga de Promociones, Busqueda o Mas vendidos, se actualiza al re-descargar y vuelve a normal si la oferta termino; la tarjeta solo se usa cuando Amazon no manda precio de lista (ofertas relampago)
- **[CORE]** `2534ca8e` Catalogo: las columnas de precios (Precio USD, Con desc., Turns, Factor) y las de Vista y Orden se pliegan; cerradas por omision y se abren con dos botones en la barra, recordando la preferencia. Los totales calculados siempre quedan a la vista y lo editado no se pierde al cerrar
- **[CORE]** `48fcc372` Rendimiento del catalogo: la tienda tardaba 7-8s porque cada producto releia de la base la tasa, el factor y los pisos de enganche decenas de veces y pedia sus categorias y fotos por separado (miles de consultas por pantalla). Ahora la configuracion se lee una vez por peticion, las categorias y fotos se precargan, y se quita un bloque muerto que calculaba los plazos dos veces
- **[CORE]** `4fce8ec9` Arregla las categorias de Amazon (el arbol normal se pide SIN type; type=standard daba 422 y caia al de mas vendidos) y enseña el error real de Amazon; Aplicar al grupo ahora actua sobre lo SELECCIONADO y lo dice en el boton; el boton semanal de precios marca y quita promociones igual que la pasada automatica
- **[CORE]** `0183a591` Promociones de punta a punta: marca la oferta al descargar, vista 0-6 y orden en el catalogo (las promos van primero sin perder su vista), re-descargar un ASIN ya importado actualiza su promocion sin tocar turns/factor/estatus, y refresco automatico diario de promos y semanal del catalogo que regresa a precio normal lo que ya no esta en oferta
- **[CORE]** `a281f63d` Categorias de Amazon en todo: el scraper baja por el arbol real (Videojuegos > PlayStation 5 > Accesorios), cada modo pide su catalogo (standard/bestsellers/deals) y el piso de enganche usa el departamento real del producto
- **[CORE]** `e45fef2c` Scraper: subcategorias reales de Amazon al elegir un departamento y modo Promociones con precio de lista y % de descuento en cada tarjeta
- **[CORE]** `944ceb19` Scraper: el dropdown de categorias de Amazon ya no se filtra (quedaba vacio) y el servidor acepta tanto nodos reales como categorias de mas vendidos
- **[CORE]** `b1a4b474` Scraper: la categoria de Amazon funciona como filtro de busqueda sin la casilla de mas vendidos, combinable con subcategoria, palabra, rango de precio y orden
- **[MX]** `01bf16c7` Pagos en pesos con Stripe Mexico ademas de dolares con Stripe EE. UU.: dos cuentas, moneda por pago con tipo de cambio del dia mas margen, tarjetas y autopago por moneda, conciliacion de depositos de las dos cuentas

**Tienda (`www-acasa-main`)**

- **[ADAPTAR]** `69ed1e069` Tienda: la tarjeta dice Promocion de acasa (nunca la etiqueta de Amazon) y la fila del inicio se llama PROMOCIONES DE ACASA, que ademas evita el choque con la seccion de marketing que ya se llamaba PROMOCIONES
- **[CORE]** `26561c80a` Tienda: insignia de descuento y pago semanal anterior tachado en la tarjeta, filtro Solo promociones y fila de PROMOCIONES en el inicio; el orden del catalogo manda
- **[CORE]** `f975178e7` La tienda agrupa por las categorias REALES de Amazon de cada producto en vez de una lista escrita a mano
- **[MX]** `7b1b1e972` Tienda: eleccion de moneda al pagar (dolares o pesos), equivalente en pesos antes de pagar y tarjetas guardadas por moneda

### 2026-09-16

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `7ae803a7` Seguridad: contrasenas de al menos 8 caracteres (politica de seguridad de la informacion)

**Tienda (`www-acasa-main`)**

- **[CORE]** `63fce3bc9` Registro y restablecer: contrasena minima de 8 caracteres (alineado con la politica de seguridad)
- **[ADAPTAR]** `8b7adbb04` Landing: fondo del hero con el degradado del diseno de Figma (180deg, 1C266B a 344ACC) y sin la malla naranja animada
- **[ADAPTAR]** `c63281de3` Landing: flecha de la foto de Mexico rehecha con el recurso original de la flecha neon (misma posicion que el diseno, colores medidos del haz del extranjero); esquina inferior derecha de la foto del extranjero sin bloque azul
- **[ADAPTAR]** `bbea2c7b1` Landing: foto de Mexico con la bandera a la derecha; flecha completa en los dorados del haz del extranjero; esquina traslucida actualizada
- **[ADAPTAR]** `92f6d8a34` Landing: punta de la flecha sobre la franja verde lisa de la foto de Mexico (sin velo sobre el escudo); el haz conserva su linea
- **[ADAPTAR]** `7a60b43ef` Landing: foto del extranjero sin franja junto a la foto de Mexico y con color igualado en la zona del haz
- **[ADAPTAR]** `f771c0eef` Landing: nueva foto de Mexico sin borde negro con la flecha original alineada; esquina traslucida de la foto del extranjero en los tonos de la nueva foto
- **[ADAPTAR]** `3017ab90a` Landing: union de las dos fotos igual a la original (suelo, haz y esquina de Mexico), banderas de EE. UU., Canada y Espana arriba
- **[ADAPTAR]** `7985a959a` Landing: foto del extranjero sin la franja verde junto a la foto de Mexico (la flecha sigue conectando)
- **[ADAPTAR]** `f2819453c` Landing: foto de Mexico sin el borde azul marino, bordes limpios como la foto del extranjero (flecha alineada)
- **[ADAPTAR]** `9462db17b` Landing: nueva foto del hero (banderas de EE. UU., Canada, Espana y Argentina) con la flecha de neon alineada a la foto de Mexico
- **[ADAPTAR]** `a3ac9cfc2` Landing movil: las dos etiquetas del hero 12 px mas arriba para no tapar las caras (mismo desfase en ambas fotos)
- **[ADAPTAR]** `4cca89953` Landing: etiqueta del hero DEL EXTRANJERO / FROM ABROAD, siempre en un solo renglon (en movil ya no tapa la foto)

### 2026-09-15

**Backend y back office (`ACACA_CODE`)**

- **[MX]** `680f8e64` Compradores en cualquier pais: pais de residencia y zona horaria, telefonos internacionales, paises atendidos configurables (bloqueos y topes), referencias en horario local, aviso de autopago cuando el banco pide confirmar (3DS), textos y correos sin 'Estados Unidos'

**Tienda (`www-acasa-main`)**

- **[MX]** `0be234b1a` Tienda para compradores en cualquier pais: pais donde vives en el registro, telefonos internacionales, comprador y referencias por pais, aviso de cobro en USD, textos de landing sin 'Estados Unidos'

### 2026-09-11

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `1bb33510` Bancos: cuentas bancarias conectadas al back office (Plaid EE. UU., cuentas manuales con importacion de estado de cuenta, saldos, movimientos, conciliacion con depositos de Stripe y gasto a un clic)

**Tienda (`www-acasa-main`)**

- **[CORE]** `ff6963cf0` Redeploy: colores originales de la tienda (main sin colores-steve)

### 2026-09-10

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `3c9f32e1` Back office: nuevo look de la propuesta (barra lateral oscura, tipografias Manrope/IBM Plex auto-alojadas, migas, tarjetas y tablas)
- **[CORE]** `203b822d` Back office reconfigurado: menu por areas, pipeline por etapas con conteos, Cliente/Cobranza/Bandeja como areas, busqueda global e indice de Configuracion
- **[CORE]** `0d0bce5e` Tarjetas guardadas: se reconocen tarjeta y Link en Perfil, autopago y cobro con un clic; alta desde Perfil solo tarjeta
- **[ADAPTAR]** `4e821240` Correo con recibo en cada pago y correo en cada etapa despues del pago inicial (datos, verificado, aprobado, firmado, entregado), con calendario de pagos
- **[CORE]** `49586b59` Admin: alerta de credito con formato 1,234.56
- **[ADAPTAR]** `bbc698c7` Candado de precio al crear contratos: si el contado del carrito ya no coincide, no se crea nada
- **[ADAPTAR]** `c9b10198` Primer pago segun la frecuencia elegida + candado al borrar articulos de un contrato

**Tienda (`www-acasa-main`)**

- **[REVISAR]** `bd52357d6` Perfil: muestra metodos guardados de tipo Link ademas de tarjetas
- **[ADAPTAR]** `2aee33809` Recibo en pantalla: pago inicial desglosado en enganche, primera cuota, exencion y cuota de procesamiento (igual que el correo)
- **[ADAPTAR]** `fbeca8aa0` Dinero siempre en formato 1,234.56 (punto decimal) sin importar el idioma del navegador
- **[REVISAR]** `944e1a922` Enganche minimo por plazo: lo financiado usa la linea completa (antes siempre el peor caso de 52 semanas)
- **[MX]** `3b4ceef82` Candado de precio: el carrito se reprecia en vivo (tipo de cambio) y el backend rechaza si el contado cambio
- **[CORE]** `b7b6567e6` redeploy
- **[CORE]** `3c0369999` Festejo de linea aprobada + carrito reparado (500), primer pago segun frecuencia y credito al cancelar

### 2026-09-05

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `d9914ccd` Migraciones GARANTIZADAS en cada deploy — tercera y definitiva: el 'Docker Command' de Render REEMPLAZA el entrypoint del contenedor, así que ni el if viejo ni el db:prepare incondicional corrían jamás (la tabla del gate se quedó sin crear dos veces). Nuevo initializer zz_migrate_on_boot: al terminar de inicializar Rails en producción, aplica las migraciones pendientes DENTRO del propio proceso — imposible de brincar, con el advisory lock del migrador (arranques simultáneos no chocan) y tronando a propósito si una migración falla. Sin pendientes cuesta una consulta.

### 2026-09-04

**Backend y back office (`ACACA_CODE`)**

- **[ADAPTAR]** `6c260670` Dos palancas de riesgo NUEVAS, apagadas por defecto (nada cambia hasta configurarlas en Seguridad → Tasas e impuestos): (1) ENGANCHE MÍNIMO POR CATEGORÍA — piso por TIPO de artículo (celulares/laptops pueden llevar más), resuelto con el mismo árbol de palabras clave de la tienda; en carritos mixtos manda el piso MÁS ALTO; base 10%; editor propio en el admin (10-90%, con Bitácora); aplica en Product#min_downpayment (el 'Desde' del catálogo lo refleja solo) y en el alta de contratos con mensaje claro. (2) TOPE DE PAGO/INGRESO (pti) — pago semanal nuevo (con exención si la eligió) + lo que YA paga en contratos activos ≤ % del ingreso semanal declarado (piso del rango, conservador); 0 = apagado; tope MÁS APRETADO configurable para expedientes que el gate marcó 'ingreso_variable' (la pieza que faltaba de la Parte I); ambos viajan por el flujo de tasas CON FIRMAS y se exponen en /settings/rates para que la tienda cotice igual.
- **[MX]** `85a2ca79` 🚀 SWITCH DE GO LIVE (Seguridad → Go live, solo master): borra TODOS los datos transaccionales de prueba en un paso — contratos, cuotas, pagos, órdenes, compradores, referencias y entrevistas, quien recibe, avales, carritos, WhatsApp, historial, tickets, compromisos, contabilidad y las cuentas de clientes de prueba (ids reinician en 1) — y CONSERVA toda la configuración: catálogo y fotos, categorías, tasas, contrato/aviso/waiver, preguntas, Motor de Riesgo con su historial, staff, CPs, tipo de cambio, Bitácora y cambios firmados. Seguridad del switch: paso 1 OBLIGA a descargar el respaldo completo (JSON de todas las tablas que se van, clientes incluidos sin contraseñas); paso 2 exige escribir 'BORRAR Y LANZAR' + confirmación; todo en una transacción; queda constancia en la Bitácora; y fija automáticamente la fecha de corte del motor de decisión (desde ese día solo cuentan datos reales). Nota: los datos de prueba de Stripe se borran en su dashboard y las llaves se cambian a producción a mano.
- **[ADAPTAR]** `0f1a2fb1` El motor de decisión IGNORA los datos de PRUEBA: nueva fecha de corte 'ignore_before' (hoy, 2026-09-04, editable en la config al lanzar) — todo contrato creado antes queda FUERA de todas las cuentas del motor (volumen, tasa de HOLD y estadísticas por regla). El panel dice desde qué fecha cuentan los datos. Los veredictos sombra por contrato siguen calculándose para todos (sirven para probar el panel), pero jamás alimentan la recomendación.
- **[CORE]** `87e74e34` Las MIGRACIONES corren SIEMPRE al desplegar: bin/docker-entrypoint ejecutaba db:prepare solo si el comando era exactamente './bin/rails server', y la forma en que Render lo pasa no coincidía — resultado: los deploys salían con código nuevo y esquema viejo (así se quedó sin crear la tabla del gate de referencias). Ahora db:prepare corre incondicional al arrancar (es idempotente); si una migración falla, el arranque truena a propósito en vez de servir a medias.
- **[ADAPTAR]** `6a9db9ff` GATE DE REFERENCIAS EN MODO SOMBRA + MOTOR DE DECISIÓN (Fases 1-6½ del plan; nada bloquea al cliente todavía). (1) La entrevista guarda cada respuesta COMPARABLE: q_key, letra de opción a/b/c y hora — además del texto de siempre. (2) Nueva tabla reference_checks: lo declarado vs lo contestado con delta CON SIGNO, marca de borde (6/24 meses no genera falsos positivos) y fuente — el empleador real (teléfono = phone_work) nunca se mezcla con un amigo contactado en su trabajo. (3) ReferenceGate: veredicto sombra clear/hold/stop POR CONTRATO con razones acumuladas (bandera roja; sobreestimó antigüedad; respuesta negativa en renta/recomendación; <2 de 4 respondieron en 5 días; patrón uniforme-instantáneo; ingreso variable = marca informativa) — guardado en el contrato, cambio a Bitácora, y solo la sobreestimación penaliza (subestimar JAMÁS; corroborar nunca sube nada). (4) MOTOR DE DECISIÓN (ReferenceGateReadiness): corre DIARIO (1 pm) sobre el libro madurado (90 días), juzga cada regla con estadística real (tasas malo disparó/limpio, lift, prueba z 95%) y emite veredicto por regla (PREDICE / NO PREDICE / DATOS INSUFICIENTES) + recomendación ENCENDER/AJUSTAR/ESPERAR con guía escrita; umbrales editables en AppSetting reference_gate_readiness_config; historial de 90 corridas; cada cambio avisa en la Bitácora. (5) Panel en admin → Motor de Riesgo: banner con la recomendación y guía, tabla por regla con los números, contratos en HOLD/STOP, y botón Recalcular ahora. El switch de la Fase 7 lo mueve una persona — el motor solo aconseja. La migración corre sola al desplegar.
- **[ADAPTAR]** `7841bc9c` Auditoría de transacciones — 2 fugas tapadas: (1) ABONO A SALDO ahora re-amortiza de verdad: el saldo insoluto real = valor presente de las cuotas pendientes a la tasa del contrato; el extra paga capital, se re-amortiza (saldo − extra) con el MISMO pago y el plazo se acorta — los intereses de las cuotas que ya no corren dejan de causarse solos (cláusulas DÉCIMA CUARTA/QUINTA). Antes se perdonaba un 25% plano del extra, que bajo el modelo amortizado regalaba de más (ej.: abono de $300 en la cuota 10 de 52 regalaba $21.44 extra). Verificado contra simulación independiente: pendiente 512.11, 25 cuotas, financiado 1018.21. (2) Al cambiar la TASA de interés (directo o con firmas), se refresca el 'Desde $X/sem' GUARDADO de todo el catálogo (el filtro por rango usa esa columna; la vitrina ya recalculaba en vivo).
- **[MX]** `3c1a0117` El CÓDIGO ahora cobra como dice el CONTRATO — interés sobre SALDO INSOLUTO (cláusula SÉPTIMA y Metodología: tasa anual FIJA ÷ 360 × días efectivamente transcurridos; semanal 7, quincenal 14, mensual 30), fuera el factor plano ×1.25. Contract.amortized_quote simula la tabla centavo a centavo (pago fijo de anualidad, la última cuota liquida el saldo exacto); build_amortization! genera esa tabla y SINCRONIZA financiado/pago con lo que la tabla cobra; el alta de contratos cotiza amortizado (el crédito sigue cubriendo el financiado completo; el plan corto ~$10/sem ACORTA el plazo); Product.weekly_annuity cotiza la tienda con la misma fórmula. La carátula imprime SIEMPRE la tasa contractual configurada (25%), nunca la equivalente re-despejada (habría dicho 13.4% y contradicho la metodología); la nota financiera describe el método real; el CAT ya calculado (TIR Banxico) sigue en la carátula. CONTRATO: fuera la línea del descuento anticipado en blanco (________ %); CUARTA ahora dice SIN incluir IVA (igual que la carátula); DÉCIMA QUINTA: pagar el saldo restante = saldo insoluto + intereses devengados, sin penalización — el ahorro de intereses es automático. Verificado contra tabla independiente: 52s $20.61/$126.77 · 39s $26.66/$94.67 · 26s $38.78/$63.24 · 13s $75.19/$32.47, CAT 28.7%. PENDIENTE (decisión de negocio): la mecánica de pagos anticipados parciales (apply_payment_saldo!) sigue con la rebaja del modelo viejo — requiere re-amortización; y los contratos YA emitidos conservan su tabla plana salvo que se regeneren.

**Tienda (`www-acasa-main`)**

- **[ADAPTAR]** `e756ffde9` La tienda espeja las dos palancas nuevas (apagadas por defecto): el carrito calcula el ENGANCHE MÍNIMO con el piso por categoría (manda el más alto del carrito; la etiqueta dice el % y por qué) y aplica el TOPE DE PAGO/INGRESO por plazo — el plan que rebasa el tope se ve atenuado con '⚠ Rebasa tu tope de pago según tu ingreso' y el checkout lo explica con números (tope, % y lo que ya paga en contratos activos), contando la exención si está marcada y el tope apretado si su expediente quedó marcado con ingreso variable. La tarjeta de precios muestra 'Enganche mínimo: X% (por el tipo de artículo)' cuando el piso es mayor al 10%.
- **[REVISAR]** `ac3120044` Texto del modo 'A saldo' alineado al modelo real: el excedente paga capital, acorta el plazo y dejas de pagar los intereses de las cuotas que ya no corren (antes prometía 'se te perdona el interés (25%)', que era la rebaja plana del modelo viejo).
- **[ADAPTAR]** `3084dea1d` La TIENDA ahora cobra como dice el CONTRATO — interés sobre SALDO INSOLUTO (cláusula SÉPTIMA: tasa anual FIJA ÷ 360 × días del periodo), fuera el factor plano ×1.25: nuevo utils/financing.js con la MISMA simulación centavo a centavo que el backend; el carrito cotiza cada plazo amortizado (pago fijo, última cuota exacta, 'A financiar' = principal + interés del plazo ELEGIDO — a 52 semanas el interés baja de $236 a $127 por cada $945: mitad de plazo ≈ mitad de interés, como manda el contrato); el piso del enganche usa el peor caso (52 sem); la tarjeta de producto y la de precios cotizan 'Desde' amortizado igual que Product.weekly_annuity. Verificado contra tabla independiente: 52s $20.61/$126.77 · 39s $26.66/$94.67 · 26s $38.78/$63.24 · 13s $75.19/$32.47, CAT 28.7% parejo.

### 2026-09-03

**Backend y back office (`ACACA_CODE`)**

- **[MX]** `4b0cc18a` Motor de riesgo SIN cables muertos: (1) los puntos de 'entrega' ya van LIGADOS a la respuesta real — México (o el dato vacío de cuentas viejas, que siempre fue México) los recibe, otro país no; hoy nadie cambia de monto porque solo entregamos a México. (2) El PARENTESCO real ya alimenta el motor: User#primary_kinship toma el del primer 'quien recibe', y User#recalculate_credit! recalcula la línea respetando lo usado (nuevo límite − usado, nunca negativa) al guardar, editar o borrar un quien recibe — y el 'Recalcular crédito' del admin usa la misma matemática (antes ignoraba el parentesco y usaba el default). Nada bloquea el guardado si el recálculo falla.
- **[MX]** `ab47e8cf` Las 'Preguntas de aprobación' del back office ahora SÍ mandan en el registro (antes eran solo una lista guardada que nada leía): GET /settings/approval_questions es público para que el formulario de registro la consulte, y la sección del admin explica QUÉ controla — las preguntas informativas (País de entrega y ¿Compartes tu ingreso?) desaparecen del registro si se eliminan/desactivan; las de puntaje siempre se preguntan porque alimentan el Motor de Riesgo; la lista de aprobación final es el guion del equipo.
- **[CORE]** `9f9c38e4` Mis tarjetas: cada tarjeta aparece UNA sola vez. La casilla premarcada del pago inicial re-guardaba la misma tarjeta en cada compra, y el perfil la mostraba repetida (parecía lista de transacciones). Ahora GET /stripe/payment_methods agrupa por 'fingerprint' de Stripe (identifica la tarjeta física), conserva la copia más reciente y desprende las repetidas al vuelo. Seguro de revertir y sin tocar el frontend: el autopago y el cobro con un clic toman la lista viva — nunca guardamos ids de tarjeta.
- **[MX]** `267288ae` Búsqueda de códigos postales A PRUEBA DE HUECOS: si el storefront pide un CP/ZIP completo (5 dígitos, con país) que no está en la tabla zip_codes, el backend lo consulta al momento en el catálogo oficial en línea (zippopotam.us — correos de EUA y México), lo guarda como caché y lo devuelve. La tabla ya tiene 31,898 CPs de México (SEPOMEX) y 37,970 ZIPs de EUA; esto cubre cualquier código nuevo o faltante para que el autollenado de ciudad/estado nunca se quede mudo.

**Tienda (`www-acasa-main`)**

- **[CORE]** `c9d2460f9` redeploy
- **[CORE]** `999bc1a6f` redeploy
- **[CORE]** `0841d605d` QUITAR ANTES DEL GO-LIVE — Sello de versión en la esquina superior izquierda de TODAS las páginas: 'v <commit corto> · <fecha y hora del build, hora del centro>'. Cambia con cada deploy de Vercel, así se ve al instante si el deploy nuevo ya aterrizó (en local dice 'v local · dev'). Es una cajita negra translúcida de 10px que no intercepta clics. El commit corto sale de NEXT_PUBLIC_VERCEL_GIT_COMMIT_SHA (Vercel lo expone solo); la hora se fija UNA vez por build en next.config.js — constante en server y cliente, sin riesgo de hydration.
- **[CORE]** `e87ce7e51` redeploy
- **[CORE]** `c2d133328` Paso 4 de ¿Cómo funciona?: ahora 'Verificamos tu información y recibes tu aprobación final', y el texto agrega la garantía: si no recibes la aprobación final, te devolvemos COMPLETOS tu enganche y tu primer pago. En español e inglés.
- **[MX]** `803b5cf3d` La lista de APROBACIÓN FINAL del back office ahora también manda en el sitio: en 'Completa tu orden' (datos del contrato) aparece la tarjeta 'Para aprobar tu orden vamos a verificar:' con las preguntas ACTIVAS de esa lista, tal como el equipo las edite en el admin. Y como el parentesco del quien recibe ya alimenta el motor de riesgo, el carrito refresca la línea de crédito justo después de guardar un quien recibe para mostrar el monto real al instante.
- **[MX]** `4a4496be3` El registro OBEDECE la lista de 'Preguntas de aprobación' del back office (conexión real de ida y vuelta): al cargar, el formulario consulta la lista maestra y las dos preguntas INFORMATIVAS — 'País de entrega' y '¿Aportas ingresos junto con alguien más en tu casa?' — se muestran solo si siguen en la lista y activas; si el equipo las elimina (como ya se hizo con la de ingresos), desaparecen del registro, sin exigirse ni enviarse. Las preguntas de PUNTAJE (vivienda, tiempos, ingreso) siempre se hacen porque alimentan el motor de riesgo. Si la lista no se puede leer, se muestran todas (el registro nunca se bloquea por esto).
- **[CORE]** `57d60bdc9` redeploy
- **[REVISAR]** `62795a001` Fuera el botón 'Acerca de nosotros' del cierre del inicio: la línea 'Cumplir sus sueños es más fácil con acasa' se queda sola, centrada, como remate de la página.
- **[CORE]** `fa12719f0` redeploy
- **[MX]** `e4f675843` Fuera el botón 'Filtros' de /productos (el '☰ Catálogo' del header ya abre el mismo panel) — y para que el celular no se quede sin filtros, el menú hamburguesa ahora también trae '☰ Catálogo'. CÓDIGOS POSTALES a 5 DÍGITOS exactos en los 4 formularios de dirección (quien recibe, tus datos, checkout y aval): el campo ya NO deja escribir más de 5 ni letras (teclado numérico en celular), y si quedan menos de 5 sale la alerta 'El código postal debe ser de 5 dígitos' al guardar.
- **[MX]** `740a3ba65` El CÓDIGO POSTAL ahora se VE y se VERIFICA en todos los formularios de dirección (quien recibe MX, tus datos EUA, checkout y aval): al escribir un CP/ZIP completo aparece una línea VERDE con la ciudad y estado reales del catálogo postal ('✓ CP 44100: Guadalajara, JAL') además del autollenado de siempre; si lo capturado NO corresponde al código, sale un aviso naranja con la ciudad/estado correctos según la base de datos (SEPOMEX para México, catálogo de ZIPs de EUA) y un botón de UN TOQUE 'Usar esta ciudad y estado'; y si el código no existe en el catálogo, aviso rojo para revisarlo. Nuevo componente compartido components/UI/ZipHint.js; nada inventado — todo sale de la tabla zip_codes del backend (31,898 CPs MX + 37,970 ZIPs EUA).
- **[REVISAR]** `b26ad6c13` El registro ya NO deja respuestas de tiempo imposibles: si el cliente dice llevar MÁS tiempo en su domicilio actual o en su empleo actual que en EE.UU., el campo se marca en rojo AL MOMENTO de elegir la opción ('No puedes llevar más tiempo en tu domicilio/empleo actual que en EE.UU. Revisa esta respuesta o tus años en EE.UU.') y también bloquea el envío del formulario (con scroll al campo con error). El mismo rango sí es válido (p. ej. '1-2 años' en ambos); solo un rango estrictamente mayor es imposible. En español e inglés.

### 2026-09-02

**Tienda (`www-acasa-main`)**

- **[CORE]** `2d22f1499` redeploy
- **[ADAPTAR]** `01248cbc0` La LÍNEA DE CRÉDITO baja AL INSTANTE al usarla (ya no hay que salir y volver): el backend aparta el crédito en cuanto se crea el contrato, pero la tienda seguía mostrando el saldo viejo hasta re-entrar. Ahora el carrito refresca los datos del cliente justo después de crear el contrato, y la página de pago inicial vuelve a refrescarlos al confirmar el pago (tarjeta o registro directo). Con eso las tarjetas ('Te alcanza ✓'), el carrito y la cuenta muestran el crédito disponible real de inmediato.
- **[ADAPTAR]** `8fb1af29a` Página ¿QUIÉNES SOMOS? (/quienes-somos) con el contenido de las láminas de acasa y el MISMO look de /como-funciona: columna blanca centrada, ceja naranja, 'Somos una empresa mexicana…' + línea naranja 'Sabemos lo que significa trabajar muchas horas y extrañar a la familia…', las 3 tarjetas (Empresa mexicana / Atención personalizada en tu idioma / Personas que entendemos tu historia), el párrafo de qué es acasa, NUESTRO EQUIPO con las dos tarjetas, y los mismos CTAs (Precalifícame / Ver productos / WhatsApp). El enlace '¿Quiénes somos?' aparece SIEMPRE en la tira del header junto a ¿Cómo funciona? (y en el menú del celular), traducible ES/EN. Corregidos typos de las láminas: 'con con'→'con', 'que adquirir'→'qué adquirir', 'idoma'→'idioma'.
- **[CORE]** `830446810` El enlace del header ahora es '☰ Catálogo' y ABRE EL PANEL DE FILTROS (como el 'Todo' de Amazon): si ya estás en /productos se desliza al instante; desde cualquier otra página te lleva a /productos con el panel ya abierto (?filters=1).
- **[ADAPTAR]** `7254f6b0b` Filas por categoría estilo Amazon en el INICIO (catálogo real, nada inventado): sección 'EXPLORA POR CATEGORÍA' después del carrusel — una fila deslizante por departamento (Electrónica, Electrodomésticos, Hogar y muebles…) con tarjetas de producto reales, flechas ‹ › al estilo Amazon en escritorio (deslizar con el dedo en celular) y 'Ver más' que abre /productos YA FILTRADO por ese departamento (/productos?cat=...). Solo aparecen departamentos con 4+ productos, máx. 12 por fila. El árbol de categorías ahora vive en utils/catalogTree.js compartido entre inicio y /productos. Sin listones de #1 más vendido ni estrellas: no hay historial de ventas ni reseñas todavía y no se inventa nada.
- **[ADAPTAR]** `681d25460` Header estilo Amazon a lo ancho de la página: fila 1 con logo, BUSCADOR grande (caja blanca + botón naranja con lupa) y carrito con contador; fila 2 con la tira de enlaces '☰ Todo el catálogo' + menú del CMS (en celular la tira se oculta y el buscador baja a su propia línea). El buscador SÍ busca: manda a /productos?q=... y la página filtra el catálogo por título/palabras clave, con chip 'Buscando: …' y ✕ para quitarla (regresa a página 1 en cada búsqueda). MÁS PRODUCTOS POR FILA: 2 en celular, 3 en tablet, 4 en escritorio (antes 1/2/3), separación más compacta, 8 esqueletos de carga y fotos con menos aire para tarjetas más chicas. Offsets al nuevo header: contenido a 150px y listón de pasos del checkout a 132px escritorio / 144px celular.
- **[CORE]** `9d2b4f445` Panel de filtros con CONTENIDO estilo Amazon: 'Empieza desde' ahora son BANDAS clicables (Todos / Hasta $50 / $50-100 / $100-200 / $200-350 / $350+, la activa en naranja) en vez del slider, y sección MARCA con checkboxes de las marcas REALES del catálogo (con conteo, varias a la vez). Categoría/Subcategoría se quedan. 'Limpiar filtros' resetea todo; el punto naranja del botón considera precio y marcas. (Sin 'Condición' ni estrellas: todo es nuevo y no hay calificaciones — nada inventado.)
- **[CORE]** `54800eac5` Filtros de /productos estilo Amazon: fuera la columna fija — ahora hay un botón 'Filtros' (con punto naranja cuando hay filtros activos) que abre un PANEL DESLIZANTE desde la izquierda sobre la página oscurecida, con ✕ y cierre al tocar el fondo. Adentro van los mismos controles (Empieza desde + Categoría/Subcategoría + limpiar). La cuadrícula de productos ahora usa todo el ancho.
- **[REVISAR]** `c1d74fa19` Pastilla 'DESDE $X USD SEMANALES': ya no se corta — el texto envuelve a dos líneas si hace falta y queda centrado vertical y horizontal (radio y altura mínima en vez de altura fija; fuera el hack de encoger la fuente).
- **[REVISAR]** `7463b0af0` Carrusel: la etiqueta de precio ahora dice 'DESDE $X USD SEMANALES' (el auto-ajuste de tamaño usa el texto nuevo para que quepa en la pastilla).
- **[CORE]** `53b3e49a1` Cierre de la portada: ahora dice 'Cumplir sus sueños es más fácil con acasa' (fuera 'Cuida de los tuyos… / ¡Si tienes ingresos, tienes tu crédito!').
- **[CORE]** `3e6b73955` FUERA la sección 'COMPRAR PARA TU FAMILIA… / SOLICITA TU CRÉDITO' (panel navy + formulario de lead) de la portada, con sus helpers de formulario ya sin uso. El cierre y el resto de la página quedan igual.
- **[ADAPTAR]** `337ed75f2` Sección de pasos (doc de Steve): título 'ASÍ FUNCIONA acasa' (fuera 'Cumplirles sus sueños…') y ahora 4 PASOS — 1 Solicita tu crédito, 2 Elige tu producto, 3 FIRMA TU CONTRATO (completamente en línea, desde tu teléfono), 4 Tu familia lo recibe en México.
- **[MX]** `bb753f69b` Tarjetas de confianza COMO EN FIGMA: 4 tarjetas blancas separadas (radio 18, sombra suave) con ICONOS ILUSTRADOS grandes a dos tintas crema+naranja — carrito, caja, cartera y persona con palomita — en vez de los emojis chiquitos. Etiquetas navy en mayúsculas con el peso real de la fuente. 2 columnas en móvil, 4 en escritorio.
- **[MX]** `f6973a16b` FUENTES COMO EN FIGMA: a-font es Antarctica VAR (fuente variable, pesos reales 100-950) pero el @font-face la clavaba en 'normal' — todas las negritas del sitio eran BOLD SINTÉTICO borroso. Ahora el rango variable está declarado y font-bold/font-extrabold renderizan los pesos verdaderos del diseño (desktop y móvil, todo el sitio).
- **[REVISAR]** `78132e06a` Chips de confianza: las 4 tarjetas sueltas ahora son UN SOLO LISTÓN blanco centrado (máx 1100px, esquinas redondeadas, mismo look que la banda del 40%) con los 4 puntos adentro; en pantallas chicas se acomodan en dos filas dentro del mismo listón.
- **[REVISAR]** `44c3bc4fd` Banda HASTA 40%: ahora es UN SOLO LISTÓN centrado (máx 1100px, esquinas redondeadas) — texto a la izquierda y el contador integrado a la derecha en la misma cinta, tamaños compactos (look 'Después' de Steve). En pantallas chicas el contador baja de línea dentro del mismo listón.
- **[ADAPTAR]** `35f21cda2` Hero: los puntos '100% en línea / Desde EUA a México / Fácil y seguro' ya NO parecen botones — texto plano con palomita naranja en una línea, sin fondo de pastilla.
- **[ADAPTAR]** `c3221f037` Portada: nueva redacción del hero (doc de Steve) — 'NO ENVÍES DINERO, ENVÍA TRANQUILIDAD.' y abajo 'Comprar para tu familia en México desde EU nunca fue tan fácil. Con acasa tú tienes el control.' (EN: Don't send money, send peace of mind / Shopping for your family in Mexico from the U.S. has never been easier. With acasa, you are in control.)

### 2026-09-01

**Tienda (`www-acasa-main`)**

- **[CORE]** `f0ad5bb40` redeploy
- **[CORE]** `85285bdc8` redeploy
- **[CORE]** `7c6a798b4` redeploy
- **[CORE]** `8fcf077ed` redeploy
- **[CORE]** `05d0fc8f0` redeploy
- **[CORE]** `27c5d3ba6` redeploy
- **[CORE]** `8dfc4fbbb` redeploy
- **[CORE]** `90298f24f` redeploy
- **[CORE]** `facf7fa91` redeploy
- **[CORE]** `33dec77c0` redeploy
- **[ADAPTAR]** `070891ff3` redeploy: hero wording to production
- **[ADAPTAR]** `82b0d1373` redeploy: hero wording to production

### 2026-08-29

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `feb7809d` Admin OPTIMIZADO PARA CELULAR (mismo tratamiento que RTO): barra lateral → barra superior fija con navegación deslizable, tablas con desliz lateral dentro de su tarjeta, pestañas deslizables, paddings compactos e inputs de 16px (sin auto-zoom del iPhone). Solo CSS — el escritorio queda idéntico.

**Tienda (`www-acasa-main`)**

- **[CORE]** `0ff982b78` Carrito y mini-carrito: botones estilo pastilla como el detalle de producto — naranja sólido redondo (Solicita / Continuar / Iniciar proceso) + secundario blanco delineado azul acasa ('Inicia sesión para continuar', 'Seguir comprando').
- **[CORE]** `9fba35791` Detalle de producto: botones estilo pastilla — 'Agregar al carrito' naranja sólido + 'Solicita tu crédito — toma minutos' delineado azul (solo visitantes).
- **[ADAPTAR]** `42f4e6582` Footer: los enlaces del pie dejan 88px a la derecha — 'Aviso de Privacidad' quedaba oculto bajo el botón flotante del carrito.

### 2026-08-28

**Tienda (`www-acasa-main`)**

- **[REVISAR]** `4b6309606` FIX botón flotante del carrito (igual que en RTO): de top:108px (chocaba con el navbar y se veía cortado) a abajo a la derecha — bottom 24px escritorio, 96px móvil.
- **[CORE]** `7853b8b0e` CARRITO SIN SESIÓN (acasa): dos botones — 'Solicita tu crédito — toma minutos' (→ /signup?next=/carrito) y '¿Ya tienes cuenta? Inicia sesión para continuar' (→ /login?next=/carrito). En la tarjeta de precios: 'Solicita tu crédito en minutos, o inicia sesión para ver tu crédito disponible.' (Espejo del cambio LTO de RTO, con el lenguaje de crédito de acasa.)
- **[MX]** `27e846d72` TRADUCCIÓN COMPLETA EN/ES (ola 2): todas las páginas del cliente ahora cambian con el botón de idioma — productos, detalle, carrito (drawer y página), login, signup (con opciones y errores), recuperar/restablecer, cuenta, perfil (con esquemas Yup), pagos, órdenes, contrato (detalle, pago inicial, pagar, datos, firmar), cómo funciona, soporte, privacidad, footer, listón del proceso, tarjetas de producto y formularios del checkout (comprador, referencias, quien recibe). Listas de opciones (KINDSHIP, JOBS, STATUS_MAP, etc.) con label_en. Fechas con locale según idioma. BONUS: pages/perfil.js le faltaba el import de Link (crashaba con pedido pendiente)
- **[CORE]** `b3a3e39fc` Navbar: los botones/links del CMS (Ingresar, Crear cuenta, Productos…) ahora se traducen con el toggle EN — diccionario NAV_EN + tNav() en los 4 puntos de render

### 2026-08-27

**Backend y back office (`ACACA_CODE`)**

- **[MX]** `b3146cbf` Scraper: selector de MERCADO (Amazon Mexico MXN / Amazon EEUU USD; Walmart y Home Depot marcados proximamente - requieren otra API) - el dominio elegido viaja en busqueda, categorias, descarga y verificacion; refresh_price y refresh_images deducen el mercado por la MONEDA del producto para catalogos mixtos; los USD nunca se reprecian por tipo de cambio (FxReprice ya filtra por moneda)
- **[CORE]** `d6555570` CLAUDE.md (mapa del sistema, matematica del credito, gotchas, reglas de marca, checklist de go-live) + docs/FORK-BUDDYRENTS.md (playbook completo del fork US rent-to-own: infra nueva, que se borra en domestico, inventario de marca, decisiones de producto, orden de trabajo)
- **[ADAPTAR]** `d1f0fc9e` Armandos Playground: barra de emojis del creador de publicaciones ampliada de 24 a 75 - organizada por identidad/CTA, compra-entrega, productos (electronica, linea blanca, herramientas), dinero-credito, celebracion, urgencia y sabor mexicano-temporadas
- **[REVISAR]** `4e93ad40` gitignore: la llave del API de 21st.dev (.21st/api-key.txt) nunca entra al repo

**Tienda (`www-acasa-main`)**

- **[ADAPTAR]** `e9374b8f3` BANDA BLANCA en primera carga (iOS): se elimina el modelo html{position:fixed}+body{100vh} heredado de locomotive-scroll y se vuelve al scroll normal del documento (Safari media solo, sin contenedor mal medido). Ademas: meta google notranslate (el sitio ya tiene su boton ES/EN) y html lang dinamico segun el idioma activo
- **[ADAPTAR]** `8e40e0232` IDIOMA ES/EN: LanguageContext (default espanol, preferencia en localStorage, seguro para SSR) + boton globo EN/ES en el navbar; primera ola traducida: banner deslizante, hero completo de portada, chips, promo y contador, tarjetas de producto (Te alcanza, From/week), pasos Como funciona y CTA movil; el resto del sitio se traduce progresivamente con t(es,en) - el fork BuddyRents invierte el default a ingles
- **[REVISAR]** `62221fd26` CAUSA RAIZ del desacomodo movil: el sitio NUNCA declaro la meta viewport - iOS renderizaba a ~980px y reescalaba (contenido empujado, banda blanca, botones flotando, se arreglaba refrescando); se agrega width=device-width en _app. Ademas: menu movil con alto automatico y scroll (h-50vh fijo desbordaba los botones de cuenta)
- **[ADAPTAR]** `3ecd99eb6` CLAUDE.md del storefront: reglas duras (styles.css real, portal del navbar, hidratacion, proporciones del hero, matematica del credito) + interruptor V2 y reglas de marca
- **[REVISAR]** `2a6cdf6fa` FIX del desacomodo intermitente en movil: el contador usaba new Date() al renderizar y el HTML del servidor casi nunca coincidia con el reloj del telefono - React reconstruia toda la pagina (brinco/pushed up que se arreglaba refrescando); ahora el reloj se fija solo en el cliente y el corte muestra -- un instante; ademas min-height 100dvh para el alto real de iOS
- **[ADAPTAR]** `eb0128aa0` Hero: el collage vuelve a ser UNO para todas las pantallas, ahora con la proporcion REAL de cada foto (994x761 y 1245x855) fijada en la caja - el minHeight de 210px era lo que rompia la geometria en movil; las flechas de neon conectan a cualquier ancho
- **[ADAPTAR]** `6dcb87c45` Hero movil: las fotos EUA/Mexico se apilan escalonadas en pantallas angostas (el collage absoluto se encimaba mal); el collage de escritorio queda identico
- **[MX]** `0892b7bc5` Tarjeta de producto: el precio semanal indica la moneda - Desde $X USD/semana
- **[ADAPTAR]** `cd40f8a94` V2 animaciones (receta del skill de motion): entrada escalonada del hero (fade+10px, 60-240ms), revelado al scroll con IntersectionObserver (fade+12px 350ms, se limpia solo para no romper hovers), tarjetas del catalogo escalonadas 35ms; sin librerias nuevas, sin JS nada se oculta (SEO), reduced-motion respetado; todo bajo UI_V2
- **[ADAPTAR]** `ea2e661f7` REDISENO V2 con interruptor de reversion (utils/uiV2.js UI_V2=false lo revierte todo; tag pre-v2 como respaldo): malla animada en el hero conservando las fotos, tarjeta de producto v2 (elevacion, zoom, Te alcanza con credito real, barra de uso, boton rapido), esqueletos de carga, pasos Como funciona en portada, CTA fijo en movil; contadores y testimonios construidos pero APAGADOS hasta tener cifras y citas reales

### 2026-08-24

**Backend y back office (`ACACA_CODE`)**

- **[ADAPTAR]** `ee682c6c` FASE DE PRUEBAS: boton de borrado real de renglones del libro (solo master) - elimina el asiento y opcionalmente el pago reconstruyendo el contrato; doble confirmacion y bitacora. QUITAR antes del go-live (marcado en codigo, rutas y UI)
- **[ADAPTAR]** `673879a9` Contabilidad: anular/reembolsar y modificar transacciones desde el registro - contra-asiento en el libro (nunca se edita el historial), reembolso Stripe opcional a la forma de pago original, reconstruccion del contrato (calendario, saldo, credito, estatus) y bitacora
- **[CORE]** `1828d4d8` Admin: cuando el token expira (Invalid token/Token expired) se regresa al login con mensaje claro en lugar de alertas confusas
- **[ADAPTAR]** `dfd35dca` FIX: el pago combinado (Hacer un pago) NO cobraba la exencion de responsabilidad - ahora la cobra por contrato con el mismo % que los pagos individuales, la reparte en el desglose contable y la registra en el libro
- **[MX]** `03bc4cbf` Recibo: el % de exencion y de IVA van junto a su monto en el desglose (se quita el renglon informativo separado)
- **[ADAPTAR]** `f1327a2b` Impresion de recibos: espera a que cargue el logo antes de imprimir (salia cortado)
- **[ADAPTAR]** `9745fd35` Recibos completos: articulos pagados, % de exencion de responsabilidad y numero de pago (ej. 6 de 26) en recibos de cliente y admin; el libro contable los guarda para reimprimir aunque el contrato se elimine (migracion 20260824060000 con backfill)
- **[ADAPTAR]** `44861033` Recibos del admin con el logo oficial (acasa_logo_mail.png) en lugar del nombre escrito - nunca se usa el acento
- **[ADAPTAR]** `f6fafa4d` Recibos: show del contrato regresa historial de pagos con folio y saldo; registro de Contabilidad con recibo imprimible por renglon y boton Imprimir del registro completo
- **[CORE]** `afc1aa69` Contabilidad con el estilo del mock: tarjetas con borde de color y etiquetas mayusculas, renglon TOTAL naranja en el registro, cajas de corte diario/mensual con desglose por categoria, % del mes, cuadre vs diarios y notas de inmutabilidad
- **[MX]** `21fe4ed0` Contabilidad: ledger append-only con categorias (enganche/renta/contado/liquidacion/EPO), cortes diario/mensual automaticos, gastos + P&L, reembolsos/contracargos/castigos, comision Stripe y FX por pago, paquete mensual al contador, pestana Contabilidad en admin

**Tienda (`www-acasa-main`)**

- **[REVISAR]** `fa323b94a` Precalificacion: pregunta de ingresos reescrita (Aportas ingresos junto con alguien mas en tu casa) y errores VISIBLES al dar Continuar - aviso junto al boton + scroll automatico al primer campo con error
- **[MX]** `0569a0fe3` Pagina Pagos: muestra la exencion por contrato y en el total (pagos a contratos + exencion + IVA)
- **[MX]** `e99aba394` Recibo del cliente: % de exencion y de IVA junto a su monto en el desglose
- **[ADAPTAR]** `fe37a2a39` Impresion de recibos del cliente: espera a que cargue el logo antes de imprimir
- **[ADAPTAR]** `05804a87b` Recibo del cliente: articulos pagados, % de exencion y numero de pago (6 de 26)
- **[ADAPTAR]** `6c012d64c` Recibos del cliente con el logo oficial (acasa_logo_mail.png del backend) en lugar del nombre escrito con acento
- **[ADAPTAR]** `2ee5d8755` Cuenta del cliente: seccion Pagos realizados con recibo reimprimible por cada pago (incluido el inicial) y boton para imprimir el calendario de pagos por separado
- **[REVISAR]** `6e847c54f` Banner: velocidad 60 px/seg = exactamente 1 pixel por frame a 60Hz - pasos uniformes, se elimina el tironeo (a 70 alternaba saltos de 1 y 2 px)
- **[REVISAR]** `4ff41fefb` Banner: loop auto-arrancable - busca el elemento en cada frame hasta que el portal lo monta (el efecto anterior corria antes de que existiera el DOM y nunca arrancaba)
- **[CORE]** `01f0283e9` Filtro del catalogo: el rango ahora es el DESDE para empezar (enganche minimo 10% del contado + primer pago semanal), misma matematica que la tarjeta de precio
- **[REVISAR]** `2882b6e2a` Fix: el banner no arrancaba - el efecto del marquee corria antes de que el portal montara el navbar (ref null); ahora depende de mounted
- **[REVISAR]** `78e701c4d` Banner nitido: marquee movido a scrollLeft con pixeles enteros via rAF (el transform animado pierde ClearType en Windows y se ve borroso); pausa con el mouse en JS
- **[REVISAR]** `df5da8a01` Banner: GPU-composited marquee (translate3d, backface-visibility, font smoothing) + integer font size for sharp text
- **[REVISAR]** `c1e1d61ad` FIX: el CSS global real es src/styles.css (globals.css no se importa) - marquee del banner y barra de scroll visible movidos ahi; el banner ahora si se desliza en una linea

### 2026-08-23

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `ae827297` Scraper: tercera casilla Foto check - selecciona solo verificados con foto principal disponible (o coincidente si ya esta en catalogo); combinable con Sold y Delivered
- **[CORE]** `1aebd7d3` Scraper: boton Verificar OPCIONAL (no obligatorio) junto a Descargar - permite usar las casillas Sold/Delivered para seleccionar; el download despues reusa la cache sin costo extra
- **[CORE]** `8b4fbf63` Scraper: casillas Sold check y Delivered check junto a Seleccionar todo - seleccionan solo los verificados con ese veredicto (interseccion si ambas), los ? no entran
- **[CORE]** `41d03a88` Catalogo: Aplicar al grupo - turns y/o factor a TODOS los productos filtrados en un clic (bulk_update extendido, recalcula el Desde por semana)
- **[CORE]** `50bcba87` Scraper: insignias APILADAS (Sold / Delivered / Foto abajo) y la Foto ahora responde tambien para ASINs nuevos: Amazon publica su foto principal (se baja PRIMERO al descargar) - verde/rojo en vez de guion
- **[CORE]** `360129f5` Scraper en UN SOLO PASO: seleccionar y Descargar (ya no hay verificacion obligatoria) - al descargar quedan guardadas las respuestas vendido/entregado por Amazon y foto principal, 1 credito por producto
- **[ADAPTAR]** `f9e1691b` Marketing (Armando's Playground): 2 textos nuevos en la biblioteca - Como funciona Acasa (post con enlace) y Que es Acasa (version corta DM)
- **[CORE]** `388ed807` Catalogo: fuera los tags Sold?/Del? por-navegador (la verdad son los chips guardados EN el producto); Actualizar precios re-estampa tambien main_photo_ok
- **[CORE]** `09db29ab` SIN verificaciones posteriores: al DESCARGAR quedan guardadas las respuestas (vendido por Amazon, entregado por Amazon, foto principal OK) y el catalogo las muestra como chips por producto; el boton del catalogo ahora es Actualizar precios (SEMANAL, manual, 1 credito por producto)
- **[CORE]** `6773858d` Catalogo: Verificar ahora usa RAINFOREST (confirmacion de costo, gratis <6h en cache) - veredicto real por fila: Amazon OK/foto OK, foto cambiada, ya no vendido-entregado por Amazon (con nombre del vendedor), o sin datos; resultados compartidos con el scraper y el equipo
- **[CORE]** `d79ef121` Fotos: la PRINCIPAL del ASIN (main_image de Rainforest) SIEMPRE va primera al importar y al re-descargar, con dedupe por ID - antes solo se usaba el arreglo images que a veces no la trae
- **[CORE]** `3357f3da` Verificaciones del scraper COMPARTIDAS en el servidor (AppSetting JSON, tope 5000): todo el equipo ve las mismas insignias Sold/Delivered/Foto en cualquier navegador; migracion suave de lo guardado localmente
- **[CORE]** `55da0fc5` Scraper: insignia neutra Foto - para ASINs nuevos (sin foto nuestra que comparar) con explicacion; la comparacion aplica al RE-verificar productos ya importados
- **[CORE]** `e424a22f` Ronda del catalogo APAGADA: la verificacion (vendedor + foto) se hace UNA vez al scrapear con 1 credito por articulo; la importacion reusa el detalle en cache sin costo extra
- **[CORE]** `f1a74314` Verificacion Amazon: diagnostico en logs (codigo de bloqueo por ASIN) y estado gris explicito No se pudo verificar en el catalogo
- **[CORE]** `30ab538e` Catalogo Verificar en Amazon: resultado EXPLICITO por fila (verde Amazon OK foto OK / rojo ya no esta / naranja foto cambiada) - antes un pase limpio no mostraba nada
- **[REVISAR]** `8c04ac80` Verificar vendedor: los ASINs verificados ANTES (cache del navegador) se re-verifican una vez para traer la comparacion de FOTO (aparece la 3a insignia)
- **[CORE]** `b8a9d5e7` Ronda automatica del catalogo (gratis, lote por tick): disponibilidad + foto principal contra la pagina de Amazon con alerta interna y Bitacora; re-descarga de fotos en 1 clic (Rainforest con cache); catalogo marca en naranja los productos con foto cambiada
- **[CORE]** `312272fb` Verificar vendedor: ademas de Sold/Delivered compara NUESTRA foto principal contra la foto principal actual del ASIN en Amazon (badge Foto verde/roja para productos ya en catalogo)
- **[MX]** `36711253` Repreciacion DIARIA peso->dolar: catalogo completo en una sola sentencia SQL (escala a miles de SKUs) + pedidos sin pago inicial (total, enganche, financiado, calendario y ajuste de credito con candado); corre con el tick del mediodia y con el boton Actualizar del admin; congelado al primer pago
- **[MX]** `b03d9ada` Fix: la lista de quien recibe tiraba 500 si la migracion de kinship no ha corrido - atributo defensivo
- **[CORE]** `79f75591` Creditos: boton Cambiar linea por cliente (master/admin) para subir/fijar la linea de credito desde esa pagina
- **[MX]** `b0014bc9` Eliminar pedido (admin): sin pagos borra directo; con pagos pregunta si procesar REEMBOLSO a la forma de pago original (Stripe misma tarjeta, multi-pago parte proporcional + IVA, manuales listados para devolver a mano) - todo en Bitacora
- **[MX]** `105e4cba` Parentesco vive ahora en Quien recibe (beneficiaries.kinship); se copia al comprador para Ordenes, contrato y motor de riesgo
- **[CORE]** `5ad72f78` Stripe: save_card opcional en payment_intent (checkbox del pago inicial); en false la tarjeta no se guarda para pagos futuros
- **[ADAPTAR]** `ca396d4e` Renombrar Seguro/Waiver a Exencion de responsabilidad en contrato (nota CAT), notas de pago y admin

**Tienda (`www-acasa-main`)**

- **[CORE]** `824f166b3` Banner deslizante (Opcion A) arriba del navbar en todo el sitio: Paisano estamos aqui PARA TI + credito sin SSN/buro + entrega en Mexico; loop continuo, pausa con el mouse, clic -> /como-funciona; offsets de layout y liston ajustados
- **[REVISAR]** `167675c77` Enlace Como funciona? siempre visible en navbar (escritorio y menu movil) y en el footer -> /como-funciona
- **[ADAPTAR]** `b7cbb7c51` Nueva pagina /como-funciona: vistazo rapido para clientes potenciales - propuesta de valor + los 6 pasos del liston + CTAs (precalificar, productos, WhatsApp)
- **[REVISAR]** `9ca857235` Liston paso 4: Verifica tu cuenta -> Verificamos tu informacion
- **[REVISAR]** `1e4817ad5` Tus datos: se quita Ingreso semanal (ya se captura en la precalificacion; el backend lo copia solo al comprador)
- **[CORE]** `e3f95c1fb` Completa tu orden: pagina ancha para que el liston se vea completo; el contenido sigue centrado y angosto
- **[CORE]** `e287d8748` Registro: titulo Crea una cuenta y precalifica tu credito
- **[REVISAR]** `3f1449c03` Liston: cabe COMPLETO en cualquier pantalla de escritorio (minWidth 700 y tipografia compacta); en celular sigue deslizable
- **[CORE]** `9b7321360` Perfil y Mi cuenta: nota clara cuando un pedido pendiente de pago inicial tiene APARTADO el credito (no es que se haya perdido) con enlace para continuarlo
- **[CORE]** `1a1d9c924` Carrito: aviso cuando un pedido pendiente de pago inicial esta apartando el credito - botones para continuarlo o cancelarlo y liberar la linea
- **[CORE]** `c859d396d` Pago inicial: pagina ancha como las demas para que el liston se vea COMPLETO; la tarjeta de pago sigue centrada y angosta
- **[REVISAR]** `fd8c93438` Liston del proceso fijo (sticky) abajo del navbar al hacer scroll
- **[REVISAR]** `6e985f14c` Barra de desplazamiento visible en toda la app (delgada, gris) - antes estaba oculta globalmente
- **[MX]** `556c702e1` Carrito: el aviso rojo de quien recibe se limpia al agregar o seleccionar la persona
- **[CORE]** `120ffbc4d` Mi cuenta es menu desplegable en el navbar (Mi cuenta / Ordenes / Perfil); se quita la lista lateral y las paginas de cuenta van centradas
- **[REVISAR]** `81e269343` Navbar: con sesion iniciada muestra nombre + sesion iniciada y el boton Crear cuenta se vuelve Cerrar sesion (escritorio y movil)
- **[ADAPTAR]** `bc0fc9dbe` Registro: se quitan los enlaces muertos Pre-califica tu credito y Aumenta tu linea; Perfil: enlace Solicitar aumento de linea por WhatsApp (mensaje precargado con nombre y numero de cliente)
- **[MX]** `46ea6fc9d` Parentesco: se quita de Tus datos y se pregunta al final del formulario de Quien recibe
- **[REVISAR]** `acf4bd50e` Tus datos: se elimina el campo duplicado Estado de residencia - se llena solo con el Estado del codigo postal
- **[ADAPTAR]** `8b7ee392f` Liston del proceso en TODAS las paginas del pedido (carrito, pago inicial, completa tu orden, contrato) - componente compartido y paso actual segun el estado real del contrato hasta la entrega
- **[ADAPTAR]** `d3ec19029` Flujo sin cuenta: liston del carrito arranca en Precalifica; tras verificar por WhatsApp la sesion inicia sola y sigue directo al carrito/pago inicial (next se conserva login->signup)
- **[ADAPTAR]** `79edc2258` Carrito: liston del proceso con flechas (Precalifica - Pago inicial - Completa tu orden - Verifica - Aprobacion final - Entrega), paso actual resaltado
- **[REVISAR]** `fb0f81535` Carrito (drawer): boton Finalizar compra ahora dice Iniciar proceso
- **[CORE]** `37ebe22f4` Pago inicial: checkbox premarcado para guardar la tarjeta en la cuenta; Mis ordenes: boton Completar mis datos para terminar despues
- **[CORE]** `e6fe924ae` Renombrar Seguro contra danos / Waiver a Exencion de responsabilidad en carrito, pagos y vistas admin
- **[MX]** `313b64c9c` Registro: Pais de entrega solo Mexico (preseleccionado)

### 2026-08-22

**Backend y back office (`ACACA_CODE`)**

- **[ADAPTAR]** `e975a9cb` Verificacion WhatsApp obligatoria: un cliente sin verificar no puede iniciar sesion ni usar la API con ningun token; override manual SOLO master/admin desde el CRM (queda en Bitacora)
- **[ADAPTAR]** `10343326` Contratos: el credito valida y consume el FINANCIADO completo (con cargo financiero), no solo el principal; al cancelar sin pagar se restaura el financiado

**Tienda (`www-acasa-main`)**

- **[ADAPTAR]** `add6a05e6` Login: cuenta sin verificar por WhatsApp no entra - mensaje claro + boton verde para verificar; se elimina la sesion legada de cliente sin token
- **[CORE]** `6b3d2e567` Carrito: el credito limita el monto A FINANCIAR completo (con cargo financiero); lo que rebasa el credito se suma al enganche
- **[CORE]** `41962e818` Producto: solo precio Desde en la pagina del articulo; plazo y frecuencia se eligen al finalizar el pago en el carrito
- **[ADAPTAR]** `353127929` Registro: el selector de lada acepta EE.UU. (+1) y MEXICO (+52) con banderitas - antes estaba filtrado solo a +1; el backend (PhoneCheck) ya validaba ambos y el WhatsApp de verificacion llega a los dos paises
- **[CORE]** `67467457b` Vista movil: la barra de 7 pasos del pedido se desliza horizontal en celular (min-width con overflow) - los pasos ya no se enciman a 390px; auditoria movil del resto de la tienda: contenedores, tablas (con overflow), formularios, selector de frecuencia y lienzo de firma (coordenadas tactiles ya escaladas) estan correctos

### 2026-08-20

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `a7d93fe0` FIX Ordenes: los paneles de verificacion por referencia y las alertas de telefono leian reference_checks/phone_alerts del nivel equivocado de la respuesta (attributes en vez de data) y por eso NO se pintaban - ahora se leen de raw; con esto ed cantu (respuesta negativa) se pinta ROJO, los positivos completos VERDE y aparecen las cajas con respuestas y fechas
- **[MX]** `33071e90` Alertas de telefono en Ordenes: cuando un numero ya fue usado como REFERENCIA (o comprador, contacto de domicilio, tel. de trabajo o quien recibe) en OTRA cuenta, la alerta incluye el NOMBRE del dueno de esa cuenta ademas del nombre del contacto (cuenta de X - orden #N); tambien se revisan los telefonos de trabajo de referencias de otras cuentas
- **[CORE]** `bd305fc7` Ordenes - historial de verificacion por referencia: si el telefono YA fue verificado en una compra ANTERIOR aparece bajo la persona (YA VERIFICADA en PED-x con fecha, respuestas completas y si recomienda); el nombre se pinta ROJO con punto rojo si hubo aunque sea UNA respuesta negativa (o no recomienda / bandera roja) y VERDE si la entrevista esta completa y todo fue positivo; cada caja se tine roja/verde segun su resultado y muestra fecha y hora
- **[ADAPTAR]** `db9b7172` Perfil: el cliente puede cambiar su CORREO (usuario de inicio de sesion) - se aplica directo sin reconfirmacion por email (la cuenta se verifica por WhatsApp) y el cambio queda en la Bitacora (email_changed)
- **[MX]** `2717e206` Renombrado en TODA la plataforma: Beneficiario -> Quien recibe (etiquetas visibles en admin, bandeja de WhatsApp, alertas de telefono y preguntas de aprobacion; los campos internos no cambian)
- **[REVISAR]** `98eee9fe` ContractSerializer: verified_sections (0-5) y approved para la barra de pasos del pedido del cliente
- **[ADAPTAR]** `18f85dbb` FIX pago combinado: la tabla payments exige id de Stripe UNICO y el pago multi creaba dos renglones con el mismo id (el segundo contrato reventaba con RecordNotUnique y el cliente veia el pago como fallido aunque Stripe SI cobro); ahora cada renglon lleva sufijo -c<contrato> y el dedupe del conjunto busca por prefijo
- **[CORE]** `b2e906d8` ContractSerializer: expone period_payment (pago exacto por periodo segun la frecuencia) para la pagina de pagos
- **[ADAPTAR]** `fb5cb4fe` PAGO COMBINADO y CUENTA COMPLETA: multi_payment_intent cobra UNA sola vez y aplica cada monto a su contrato (finalize/webhook multi); autopay_all activa el pago automatico de TODOS los contratos con la tarjeta guardada y los contratos nuevos nacen igual (users.autopay); set_frequency cambia semanal/quincenal/mensual recalculando el calendario pendiente manteniendo el saldo. MIGRACION: bin/rails db:migrate
- **[CORE]** `118d270a` Stripe: SetupIntent para guardar TARJETA sin pagar (Perfil - pagos automaticos) y DELETE payment_methods/:id para quitar una tarjeta guardada (verifica que pertenezca al cliente)
- **[ADAPTAR]** `6a078bbb` Guardado quiet desde el PERFIL: editar comprador o referencias con quiet=1 NO dispara los WhatsApps de verificacion - esos solo se envian al hacer/completar un pedido
- **[ADAPTAR]** `75ab1261` Datos del comprador y referencias SIN volver a capturar: se prepueblan desde CUALQUIER compra anterior con datos (antes solo compras aprobadas) - verificados hace menos de 6 meses se copian solos, en cualquier otro caso se muestran para CONFIRMAR o actualizar; el paquete de WhatsApps de verificacion ahora deduplica POR CONTACTO: si el cliente actualiza una referencia despues del primer envio, SOLO el contacto nuevo recibe su mensaje (sin repetir a los demas)

**Tienda (`www-acasa-main`)**

- **[CORE]** `bb9db3724` Completa tu orden (cliente que regresa): si hay datos de una compra anterior aparece Ya tenemos tus datos con boton Mis datos siguen igual (confirma con un clic via confirm_datos) y los formularios de Tus datos y Referencias abren PRELLENADOS con lo anterior (copias nuevas para esta compra, sin tocar la orden previa) - nunca se captura desde cero
- **[ADAPTAR]** `c213cacdd` Perfil: campo de correo EDITABLE con validacion y aviso de que es el usuario de inicio de sesion (antes estaba bloqueado)
- **[MX]** `8bf0959d2` Renombrado de cara al cliente: Beneficiario -> Quien recibe en toda la tienda; Comprador -> Tus datos en los textos del cliente (titulos, pasos, avisos y menu); los nombres internos de campos no cambian
- **[CORE]** `19af6e149` Barra de PASOS en cada pedido (Ordenes del cliente): Pago inicial > Tus datos > Verificacion > Aprobacion > Firma > En camino > Entregado - cada paso verde con palomita al completarse, el actual en naranja con halo y una pista de que sigue (con avance 3/5 en verificacion); la linea de progreso se pinta en verde
- **[MX]** `5ba62d181` El CODIGO POSTAL manda en TODAS las direcciones: al capturar el CP, ciudad y estado se llenan SOLOS desde el catalogo y se corrigen si no coinciden (helpers compartidos: aplica a comprador, beneficiario, aval y formularios del area de clientes); CP con varias ciudades deja elegir pero valida contra la lista; guardar con ciudad/estado que no corresponden queda BLOQUEADO con mensaje claro
- **[ADAPTAR]** `223150d70` Pagos: cada contrato muestra sus ARTICULOS (miniatura + descripcion, con +N mas si hay muchos) para que el cliente sepa que esta pagando
- **[ADAPTAR]** `59f3eb975` Pagos por PERIODOS COMPLETOS: cada contrato muestra su proximo vencimiento y el pago se ajusta con - y + de pago en pago segun SU frecuencia (semanal/quincenal/mensual); cada pago extra recorre la fecha - se muestra Al corriente hasta con la nueva fecha; en 0 el contrato no entra al pago y al cubrir el saldo dice Liquida este contrato
- **[ADAPTAR]** `73f711fa2` Mi cuenta: totales sobre TODOS los contratos con saldo; Hacer un pago abre /pagos (nueva pagina): lista todos los contratos, monto ajustable por contrato y UN solo pago con tarjeta; Perfil: pago automatico de TODA la cuenta (con tarjeta guardada) y frecuencia semanal/quincenal/mensual por contrato
- **[CORE]** `7d9308b1d` Perfil: seccion Tarjeta para pagos automaticos - agregar tarjeta SIN pagar (Stripe Elements/SetupIntent), lista de tarjetas guardadas (marca y ultimos 4) y quitar tarjeta
- **[ADAPTAR]** `ee6bde0d1` Perfil -> Mis datos de verificacion: el cliente actualiza referencias, contacto de domicilio y trabajo desde su perfil (formularios prellenados de su compra mas reciente); editar aqui NO manda WhatsApps (quiet) - solo se envian al hacer un pedido
- **[REVISAR]** `3179491d6` Confirmacion de datos previos: texto correcto tambien cuando la compra anterior aun no estaba verificada (revisa, confirma con un clic o edita solo lo que cambio)
- **[ADAPTAR]** `82fe11c0c` Mi cuenta: la tarjeta Saldo por pagar se vuelve BOTON cuando hay saldo (borde naranja + Hacer un pago) y lleva directo a pagar - primero al contrato VENCIDO si lo hay, si no al primero con saldo; con saldo cero queda como tarjeta informativa

### 2026-08-19

**Backend y back office (`ACACA_CODE`)**

- **[MX]** `f7b323d4` ALERTA de telefonos repetidos en la orden: cada numero de la compra (cliente, comprador, beneficiario, referencias, contacto de domicilio, telefonos de trabajo) se revisa contra TODA la base (cuentas, compradores, referencias, beneficiarios y domicilios de otras compras); banner arriba de la verificacion - AMARILLO si el nombre coincide (misma persona), ROJO si el nombre NO coincide (posible fraude); la propia cuenta del cliente no genera falsa alarma
- **[CORE]** `1b5baebb` Ordenes: las comunicaciones de verificacion se documentan BAJO CADA PERSONA - cada referencia, el contacto de domicilio y el trabajo muestran su propio panel con el estado (sin contacto / mensaje enviado / nos escribio / entrevista en curso / completa / pospuesta / bandera roja), si recomienda o no, y las preguntas con sus respuestas de la entrevista; ya no es un area general
- **[ADAPTAR]** `ffc39ec3` Soporte: cuando el cliente vuelve a escribir con ticket ABIERTO ahora recibe respuesta (Tu solicitud T-x sigue EN PROCESO...) - texto editable soporte_en_proceso en Respuestas WhatsApp; antes el mensaje repetido se anotaba en el ticket pero el cliente quedaba en silencio
- **[ADAPTAR]** `4523057a` Respuestas de SOPORTE en el repositorio editable (Respuestas WhatsApp): soporte_recibido (acuse al abrir el ticket, variables nombre y ticket) y soporte_resuelto (aviso AUTOMATICO al cliente al resolver, con la resolucion); el resultado del aviso queda anotado en el ticket
- **[REVISAR]** `38893b3a` Tickets de soporte con FECHA Y HORA: en el seguimiento (notas), en la apertura del ticket, en la resolucion y en la columna Actualizado de la lista
- **[ADAPTAR]** `bde7f933` Tickets de soporte: ACUSE inmediato por WhatsApp al abrir el ticket (Recibido! Abrimos tu solicitud, ticket T-x, te respondemos en breve); si el numero ya tiene un ticket ABIERTO, el nuevo mensaje se anota en ese ticket y lo sube al frente de la lista (sin duplicados)
- **[ADAPTAR]** `7e92086d` SOPORTE con TICKETS (pagina bajo la linea): tickets por cliente gestionados hasta su RESOLUCION - estados abierto/en proceso/esperando cliente/resuelto (resolver exige escribir COMO se resolvio), prioridades, quien atiende, notas de seguimiento, busqueda y contadores clicables; AUTO-TICKET cuando el cliente escribe desde el boton de Soporte del sitio (uno abierto por telefono); boton WhatsApp directo desde el ticket. Ademas TODAS las conversaciones se ligan SIEMPRE a la cuenta VERIFICADA del numero (User.by_whatsapp_tail: verificada mas antigua; duplicados sin verificar ya no se llevan el hilo). MIGRACION: bin/rails db:migrate
- **[ADAPTAR]** `9ce9d93d` Soporte por WhatsApp: los hilos que llegan pidiendo ayuda (boton de la pagina de Soporte, saludo precargado) se marcan con pill roja SOPORTE en la bandeja
- **[ADAPTAR]** `08041537` Gestion de cuenta sube ARRIBA de la linea (visible para todo el equipo operativo, junto a WhatsApp); bajo la linea queda solo administracion (Marketing, Respuestas WhatsApp, Creditos, Catalogos, Configuracion, Seguridad). El boton Eliminar cliente dentro del workbench sigue siendo solo master/admin
- **[ADAPTAR]** `a5f31f46` Respuestas WhatsApp sale de Configuracion y se vuelve su PROPIA seccion bajo la linea (credenciales de administracion), con su entrada en el menu junto a Gestion de cuenta; Configuracion regresa a sus 3 pestanas originales
- **[ADAPTAR]** `0abcb2cb` Respuestas WhatsApp: plantillas de Meta INLINE - lista con estado en vivo (verde Aprobada, En revision, Rechazada con motivo de Meta), boton Actualizar estado, envio DIRECTO a Meta para aprobacion desde la misma pestana (nombre, idioma, categoria, texto con variables y ejemplos; el emoji-bar tambien funciona ahi) y eliminar solo master/admin
- **[ADAPTAR]** `f6ea6c83` Configuracion -> Respuestas WhatsApp (nueva pestana): repositorio EDITABLE de todas las respuestas automaticas (verificado, aprobada, firma, paquete de reenvio, entrevista) con sandbox de emojis, variables que se rellenan solas y boton Original; seccion de plantillas de Meta (constructor) para los mensajes fuera de 24h; ALERTAS INTERNAS: si un disparador automatico falla (webhook, tick, aprobacion, firma, entrevista, reenvio) se manda WhatsApp a los numeros del equipo configurados (anti-tormenta 10 min) y queda en la Bitacora
- **[ADAPTAR]** `b5ad675f` Enlaces HUMANOS en WhatsApp: los mensajes de reenvio usan el enlace corto www.acasamx.com/wa (la pagina redirige a nuestro chat con saludo listo; la identificacion es por telefono, no por el texto); el cierre de la entrevista lleva BOTON de enlace (Conocer Acasa) via cta_url en lugar de URL fea
- **[REVISAR]** `db810899` Entrevista de verificacion 100 por ciento de OPCION MULTIPLE: 4 preguntas, cada una con 3 botones de UN toque; los rangos de tiempo son los MISMOS del proceso de aprobacion (menos de 6 meses / 6 meses a 2 anos / mas de 2 anos); respuestas negativas marcan advertencia en el historial y bajan la recomendacion; texto libre durante la entrevista reenvia la pregunta con sus botones
- **[ADAPTAR]** `819ddaa0` Hilo de WhatsApp en ORDEN: el webhook archiva PRIMERO el mensaje entrante y DESPUES manda la respuesta automatica (antes la respuesta quedaba con milisegundos de ventaja y se pintaba arriba de la pregunta); desempate estable por id al ordenar mensajes del mismo segundo
- **[ADAPTAR]** `ea5a1f55` ELIMINAR (solo master/admin, todo a la Bitacora): 1) Cliente COMPLETO desde Gestion de cuenta - funcion de PRUEBAS marcada para quitar al salir en vivo - borra cuenta, contratos, pedidos, pagos, verificaciones, compromisos, carritos, historial y WhatsApp (con adjuntos); 2) Pedido completo desde Ordenes (contrato + articulos, restaura credito); 3) Cuenta nueva desde el CRM. Confirmaciones fuertes en los tres
- **[CORE]** `d4dd65f7` ENTREVISTA de verificacion con el guion completo, MAXIMO 4 preguntas, en tiempo real (cada respuesta dispara la siguiente pregunta al instante): dueno de casa, empleador, referencia MX y referencia USA; apertura con botones (Si adelante / Ahora no); transcripcion en reference_pings.answers; cada Q&A al historial; BANDERA ROJA automatica si dice no conocer al cliente. MIGRACION: bin/rails db:migrate
- **[ADAPTAR]** `2be8d510` Mini-entrevista por WhatsApp con BOTONES cuando la referencia nos escribe: 1) Cliente esta solicitando credito en Acasa... Recomiendas a X? [Si, lo recomiendo][No] - No: gracias + invitacion a solicitar su propio credito; Si: 2) Desde hace cuanto lo conoces / vive ahi / trabaja ahi? [Menos de 6 meses][1 a 2 anos][Mas de 2 anos]. Respuestas en reference_pings (recommends, time_known) y en el historial. MIGRACION: bin/rails db:migrate
- **[REVISAR]** `6b1a641b` Verificacion de referencias SIN plantillas automaticas: el paquete de reenvio hace que las referencias nos escriban (ventana abierta, conversacion libre); las plantillas ref_* quedan solo para contacto MANUAL desde el selector. Cuando una referencia pendiente nos escribe, su registro pasa a respondio y se anota en el historial del cliente
- **[ADAPTAR]** `be878770` Paquete de REENVIO al completar datos: el cliente recibe por WhatsApp un mensaje listo para reenviar a cada referencia, al contacto de domicilio y al trabajo, con enlace wa.me y texto precargado - al tocarlo nos escriben y su ventana de 24h se abre (verificacion en conversacion libre). Ademas el telefono del TRABAJO del comprador tambien entra a la verificacion directa por plantilla. Una sola vez por contrato
- **[ADAPTAR]** `4b773f27` Contrato: el campo Modelo ya se llena con el modelo del articulo desde el catalogo (products.model_number); con varios articulos se numera igual que la descripcion. Sin migracion
- **[ADAPTAR]** `9d81ae09` Bandeja WhatsApp: cuando VARIAS cuentas comparten el mismo telefono, el hilo lo avisa (N cuentas con este tel.) - todo lo de un numero cae en UNA sola conversacion, igual que en WhatsApp
- **[ADAPTAR]** `937b39f6` Cuenta APROBADA: aviso automatico por WhatsApp al cliente (evento aprobada, plantilla cuenta_aprobada); Enviar a firma manda el enlace por correo Y WhatsApp siempre; script scripts/tpl_aprobada.rb crea la plantilla en Meta
- **[CORE]** `625583dd` Verificacion por 5 SECCIONES en Ordenes: se agregan RESIDENCIA (direccion, tipo de vivienda, contacto de domicilio con boton de conversacion, comprobante de domicilio) y EMPLEO (trabajo, tel. del trabajo con conversacion, ingreso, comprobante de ingresos) ARRIBA de las referencias, cada una con palomita y comentario propios; el comprador queda solo con identidad. Semaforo y aprobacion ahora exigen 5/5. MIGRACION: bin/rails db:migrate
- **[ADAPTAR]** `45a51579` ALERTA de telefono duplicado: si una cuenta NUEVA se registra con el telefono de una cuenta EXISTENTE ya verificada por WhatsApp, (1) correo inmediato al equipo (NOTIFICATE_TO) comparando ambas cuentas, (2) evento en la Bitacora, (3) pill roja Tel. de otra cuenta en CRM Cuentas nuevas con el numero y nombre del titular original. No bloquea el registro; deja revisar antes de dar credito
- **[ADAPTAR]** `8e52f138` La respuesta automatica de verificacion (Verificado! tu cuenta ya esta activa) ahora se ARCHIVA como mensaje saliente: era el unico envio de toda la app que no se guardaba, por eso no aparecia en la bandeja de WhatsApp del admin ni en el hilo del cliente
- **[CORE]** `4a2d94eb` Configuracion con PESTANAS: General / Motor de Riesgo / Preguntas de aprobacion. Motor de Riesgo deja de ser entrada del menu y vive como pestana de Configuracion; las Preguntas de aprobacion (pre-aprobacion y aprobacion final, con agregar/editar/reordenar/activar/eliminar) tienen su propia pestana siempre visible

**Tienda (`www-acasa-main`)**

- **[ADAPTAR]** `8c5009030` Completa tu orden: al terminar comprador + referencias el boton se vuelve VERDE Finalizar por WhatsApp con aviso claro - te enviamos por WhatsApp los mensajes de verificacion listos para reenviar a tus referencias, contacto de domicilio y trabajo; tambien reconoce datos ya existentes (antes decia Completar despues aunque todo estuviera capturado)
- **[ADAPTAR]** `600265ef0` Aviso de Privacidad ENLAZADO en todas sus entradas: en el registro el enlace ya abre /privacidad (antes era un enlace muerto a #); en el footer aparece SIEMPRE (aunque el CMS no lo traiga); y /privacy redirige a /privacidad por si algun enlace viejo usa la ruta en ingles
- **[REVISAR]** `5df1a3990` Enlace a SOPORTE en el footer (siempre presente, aunque el CMS no lo traiga) y en Mi cuenta: Necesitas ayuda? junto al saludo
- **[ADAPTAR]** `9793a780b` Pagina de SOPORTE en www.acasamx.com/soporte: boton grande de WhatsApp con saludo de ayuda precargado (llega a la bandeja del equipo identificado como soporte), numero visible y horario de atencion
- **[ADAPTAR]** `253b87fac` Mi expediente: boton Editar mis datos - el cliente puede cambiar referencias, domicilio (contacto de casa) y empleo desde su pedido; abre los formularios prellenados; se oculta cuando el contrato ya esta firmado
- **[ADAPTAR]** `eb5b90373` Enlace corto www.acasamx.com/wa: redirige a nuestro WhatsApp con saludo precargado (para los mensajes que el cliente reenvia a referencias, dueno de casa y trabajo)
- **[REVISAR]** `6cf539c83` Formularios de Comprador y Referencias: el clic FUERA del panel ya NO cierra (se perdia todo lo capturado); solo la X descarta o Guardar guarda

### 2026-08-18

**Backend y back office (`ACACA_CODE`)**

- **[MX]** `ba6bb704` Tick programado: POST /api/ticks/run (protegido con TICK_SECRET) que corre lo recurrente cada 15 min via el Cron Job acasa-tick de Render: verificaciones de referencias (horario local), recordatorios de compromisos (9am Monterrey) y tipo de cambio diario (12pm). Sustituye al worker de Sidekiq que nunca existio en acasa-web
- **[ADAPTAR]** `e494fd62` Verificacion AUTOMATICA de referencias por WhatsApp + contacto de domicilio + Preguntas de aprobacion. (1) El comprador ahora captura CONTACTO DE DOMICILIO (casero o conocido, con lada). (2) Al completarse los datos se encolan solas: ref_personal al telefono de cada referencia, ref_trabajo al del trabajo y ref_domicilio al contacto del domicilio; un job cada 15 min las envia SOLO en horario local 8am-9pm (MX 10-19h Centro cubre todos los husos de MX; US 12-21h Este cubre del Este a Alaska) y solo cuando Meta ya aprobo la plantilla; todo queda en el hilo y la bitacora de la persona. (3) Motor de Riesgo: pagina Preguntas de aprobacion (pre-aprobacion y aprobacion final) con agregar/editar/reordenar/activar/eliminar, auditada. MIGRACION: bin/rails db:migrate
- **[ADAPTAR]** `f3722289` El mensaje de Verificado por WhatsApp incluye el ENLACE a la tienda (https://www.acasamx.com, clickeable en WhatsApp) para que el cliente empiece a comprar de inmediato
- **[ADAPTAR]** `ce2deb03` Plantillas en TODOS los botones de WhatsApp: el popup de conversacion (CRM, cuentas nuevas, carritos, banco de trabajo, ordenes) ahora tiene boton Plantilla y, si el texto libre falla por la ventana de 24h, abre solo el selector de plantillas con vista previa. El selector se generalizo con callback para funcionar desde cualquier pantalla
- **[ADAPTAR]** `aee8383e` CRM: seccion CUENTAS NUEVAS SIN COMPRA - registrados que nunca regresaron (sin carrito ni pedido), con estado de verificacion WhatsApp, tiempo esperando, contacto por WhatsApp y correo (textos sugeridos segun si verificaron o no) y boton LIBERAR que los saca del seguimiento sin borrar la cuenta (queda en Bitacora). MIGRACION: bin/rails db:migrate
- **[ADAPTAR]** `8a666e2d` Correo de bienvenida: VERIFICACION POR WHATSAPP funcionando. El mailer nunca seteaba whatsapp_url (solo confirmation_url) asi que el boton de verificar jamas aparecia; ahora genera el token del cliente y arma el enlace wa.me con el codigo ya escrito (numero de la empresa desde ENV o consultado a Meta y cacheado). Boton verde principal + verificacion por correo como alternativa + copy con los 3 pasos de la compra

**Tienda (`www-acasa-main`)**

- **[ADAPTAR]** `6111b25db` Datos del comprador: CONTACTO DE DOMICILIO obligatorio (casero o conocido de la vivienda, nombre y telefono con lada) para la verificacion de renta/propiedad por WhatsApp

### 2026-08-08

**Backend y back office (`ACACA_CODE`)**

- **[ADAPTAR]** `445f4c11` COMPROMISOS DE PAGO automatizados: al registrarlos se avisa al cliente por WhatsApp y un job diario manda SOLO el recordatorio el dia ANTERIOR a la fecha (plantilla si la ventana de 24h esta cerrada). Historial de la cuenta al FONDO del banco de trabajo con WhatsApp+correos+llamadas+compromisos, buscador, filtro por tipo y por rango de fechas. El chat de WhatsApp ya NO muestra notas internas (solo mensajes reales). MIGRACION: bin/rails db:migrate
- **[ADAPTAR]** `ff810722` WhatsApp: CONSTRUCTOR de plantillas en el admin (crear y mandar a revision de Meta, ver estado y motivo de rechazo, eliminar) y asignacion de que plantilla usa cada aviso automatico. Nuevo WhatsappOutbound: los avisos de la plataforma (firma de contrato, cobranza, carrito, primer contacto) intentan texto libre y, si la ventana de 24h esta cerrada, se reenvian SOLOS como plantilla aprobada. Ademas PhoneCheck: valida telefonos al guardarlos (EE.UU. 10 digitos con lada real, Mexico +52 y 10) y marca con advertencia a los clientes con telefono mal capturado
- **[ADAPTAR]** `44c4fe7a` Plantillas: cada variable se identifica y se autollena segun el texto (Nombre, Contrato, Monto, Articulos y ENLACE). Los enlaces se arman solos: firma_contrato -> /contratos/ID/firmar, recordatorio_pago -> /cuenta, carrito_pendiente -> /carrito. Cada campo muestra su etiqueta
- **[REVISAR]** `4c85720a` Plantillas: no cachear una lista VACIA (antes, si la primera consulta fallaba, el selector quedaba vacio toda la sesion) y mostrar el error del API si lo hay
- **[ADAPTAR]** `9107f0ee` PLANTILLAS de WhatsApp conectadas: la plataforma ya puede INICIAR conversacion con cualquier numero. send_template + listado de plantillas aprobadas (GET whatsapp/templates), boton Plantilla en el chat, y si el texto libre falla por la ventana de 24h se ofrecen las plantillas automaticamente con vista previa y variables. Ademas se guarda el MOTIVO exacto de no entrega que reporta Meta (status_error) y la burbuja muestra 'no entregado' con el detalle. MIGRACION: bin/rails db:migrate
- **[ADAPTAR]** `9a6086d9` CRM: comunicacion con el cliente por CORREO ademas de WhatsApp. Boton correo en ventas por cerrar y en carritos abandonados (con textos sugeridos), boton Correo en el banco de trabajo, redactor emergente y POST /api/contact_logs/email que envia con el SMTP de la plataforma (plantilla Acasa) y deja el envio registrado en la bitacora de la persona
- **[REVISAR]** `e273c87f` Past Due Stats: los porcentajes ahora son sobre el TOTAL DE CUENTAS ACTIVAS (cada cubeta = sus clientes / activas) y se agrega la cubeta TOTAL VENCIDO al extremo derecho (suma de todas las cubetas vencidas, con su monto y su % de la cartera activa; clic filtra a todos los clientes con atraso)
- **[ADAPTAR]** `943dae88` Past Due Stats con los MISMOS rangos que Account Aging (1 a 7 / 8 a 14 / 15 a 30 / 31 a 60 / 61+) y Account Aging se MUEVE de Contratos a Gestion de cuenta (boton en el encabezado; Contratos queda solo con el detalle del contrato)
- **[ADAPTAR]** `9e58fd0d` Miniaturas de producto con clic para AGRANDAR (lightbox: foto grande con titulo; clic o Esc cierra) en Ordenes, verificacion, detalle del contrato y banco de trabajo
- **[ADAPTAR]** `9a1378c8` Miniaturas del PRODUCTO para atender al cliente viendo lo que compro: en las filas de Ordenes, en la pantalla de verificacion (por articulo), en el detalle del contrato y en las tarjetas del banco de trabajo de Gestion de cuenta (item_thumbs en el serializer)
- **[ADAPTAR]** `1ae6be5f` Ordenes: se retira el boton WhatsApp al cliente de la barra de acciones (el contacto queda en los botones de conversacion junto a cada persona)
- **[ADAPTAR]** `2a655b35` HOTFIX pagos: el endpoint de la llave publicable se llamaba config y chocaba con el config interno de Rails (recursion infinita -> No se pudo iniciar el pago); renombrado a publishable_config. + El CONTRATO se crea hasta pulsar Generar contrato y enviar a firma: el pago inicial ya NO asigna numero (payment.rb), contado tampoco nace numerado (se quita ensure_number), y el pipeline corre completo aunque el saldo sea cero; botones de Ordenes se activan por contract_id
- **[CORE]** `d9744af3` Compras de CONTADO siguen el proceso completo: ya no se marcan liquidadas al pagar; pago inicial -> comprador y 4 referencias (aplica tambien a contado) -> verificacion -> firma -> entrega, y SOLO entonces liquidado. Arregla ordenes de contado que desaparecian de Ordenes del cliente y del pipeline
- **[ADAPTAR]** `1a2527e6` WhatsApp EN VIVO + palomitas de entrega: la bandeja y la conversacion abierta se actualizan solas cada 7s (sin refrescar, sin perder lo escrito); mensajes salientes guardan el id de Meta y el webhook procesa statuses -> palomitas (sent/delivered/read/failed) en cada burbuja. MIGRACION MANUAL: bin/rails db:migrate

### 2026-08-07

**Backend y back office (`ACACA_CODE`)**

- **[ADAPTAR]** `d22cc57b` Ordenes: boton principal Comprar en Amazon en la barra de acciones DESPUES de Generar contrato; bloqueado (rojo, deshabilitado) hasta orden aprobada Y contrato firmado; amarillo abre los articulos pendientes en Amazon; verde al completarse
- **[ADAPTAR]** `1988384d` Separacion contrato/operacion + SEMAFORO en Ordenes: el detalle del contrato queda SOLO informativo (sin Comprar en Amazon; enlace Ver en Ordenes); pipeline con 5 pasos rojo/amarillo/verde (Verificacion, Aprobacion, Contrato y firma, Compra Amazon, Entrega); Comprar se habilita hasta orden aprobada Y contrato firmado; botones cambian de color segun avance
- **[ADAPTAR]** `eb820449` Gestion de cuenta: lista por CLIENTE (una fila, conteo de contratos; cubetas filtran clientes) + BANCO DE TRABAJO por cliente: contacto WhatsApp/llamada/ficha, notas y COMPROMISOS DE PAGO, proximo vencimiento editable (adelantar=tiempo libre, regresar=vuelve a deber), pagos del cliente SOLO aqui (efectivo/transferencia/tarjeta guardada/tarjeta nueva via Stripe Elements), DEVUELTO/CASTIGAR tras el drill; se retira pago y fecha del detalle del contrato; Stripe: cobros del staff cargan al cliente dueno del contrato + GET config
- **[REVISAR]** `1e758eb5` Gestion de cuenta: la seccion de cubetas se titula Past Due Stats
- **[REVISAR]** `29b3fd37` Gestion de cuenta: cubetas de antiguedad de cartera vencida (Al corriente / 1-30 / 31-60 / 61-90 / +90 dias) con conteo, monto vencido, % del total y clic-para-filtrar; columnas Vencido y Dias en la tabla
- **[ADAPTAR]** `0469eb2b` Marketing: accesos rapidos Ver pagina de Facebook y Ver Instagram (abren el perfil real en ventana nueva)
- **[ADAPTAR]** `d6d760ab` Gestion de cuenta como seccion propia BAJO LA LINEA (buscar/filtrar contratos, DEVUELTO/CASTIGAR/Reactivar desde ahi; se quita del detalle del contrato) + Marketing movido bajo la linea (admins; admin_redes solo ve Marketing) + retitulado Armando's Playground
- **[ADAPTAR]** `0b737ac6` Marketing: Biblioteca de publicaciones (textos guardados editables con los 3 posts para grupos precargados, publicar en Facebook con 1 clic, Usar/Copiar) + creador con barra de emojis y boton Negrita Unicode que se conserva en Facebook/WhatsApp
- **[ADAPTAR]** `76b4206a` Aviso de privacidad EDITABLE en Control de documentos legales (GET publico /api/settings/privacy para www.acasamx.com/privacidad; cambios con firmas de administradores; rol sistema aplica directo)

**Tienda (`www-acasa-main`)**

- **[ADAPTAR]** `2238da03b` Pagina /privacidad ahora muestra el aviso EDITABLE servido por el API (settings/privacy) con fecha de ultima actualizacion
- **[ADAPTAR]** `f251f5eaa` Aviso de Privacidad publico en /privacidad (requisito de Meta para publicar la app; ARCO, WhatsApp, cookies, transferencias)

### 2026-08-06

**Backend y back office (`ACACA_CODE`)**

- **[MX]** `535aabf8` WhatsApp Nuevo chat: directorio COMPLETO de contactos (clientes, usuarios del equipo, compradores, beneficiarios y referencias con telefono) para iniciar el chat por nombre; numero manual sigue disponible
- **[ADAPTAR]** `3b15e23b` WhatsApp: boton Eliminar chat en rojo oscuro con texto, bien visible en el encabezado del hilo
- **[ADAPTAR]** `fd194a4a` WhatsApp: boton para eliminar la CONVERSACION completa de un telefono (mensajes + notas), solo master/admin, registrado en la bitacora
- **[ADAPTAR]** `8b4f6c79` WhatsApp: NUESTRO numero de envio en el encabezado de la pagina (consultado a Meta, cache 12h) y el numero del contacto como tooltip al pasar el mouse por el encabezado del chat
- **[ADAPTAR]** `e447ac00` Popup de conversacion: eliminar mensajes de WhatsApp y notas tambien desde el popup (solo master/admin; queda en la bitacora)
- **[ADAPTAR]** `cd238d07` WhatsApp Nuevo chat: nunca agrega el 1 de EEUU (WhatsApp lo pone solo); +52 explicita salvo que ya venga; numeros con + se respetan; quita el 1 inicial si lo escriben
- **[ADAPTAR]** `15f1e769` Verificacion: selector de lada (+52/+1/otra) en telefonos de referencias; EE.UU. se guarda sin lada (WhatsApp la agrega solo), +52 explicita
- **[CORE]** `5d27f73c` Admin: cuentas de CLIENTE no entran al panel; el login las rebota con aviso (la tienda es su lugar) y descarta el token
- **[CORE]** `d14f4914` Perfil del cliente: autorizar por id del usuario del token (JWT); la comparacion legada por encabezado ClientNumber devolvia 403 a TODOS los clientes al ver/editar su propio perfil
- **[ADAPTAR]** `552a16c2` Pestana Marketing: Facebook + Instagram (publicar/programar, publicaciones con metricas, comentarios con respuesta; acceso master/admin/sistema/admin_redes); WhatsApp: eliminar mensajes y notas SOLO master/admin (bitacora); fix boton Ficha desde la bandeja y boton Llamar (copia numero + tel: + guia Phone Link)
- **[ADAPTAR]** `2989f5ec` WhatsApp: Nuevo chat a cualquier numero (lada + numero, detecta hilos existentes) y boton Llamar (tel:) con nota de llamada lista para registrar en la pagina de la persona
- **[MX]** `1fec4856` Bandeja de WhatsApp en el admin: pagina de conversaciones (clientes, compradores, beneficiarios, referencias) con hilos por persona donde cae TODO lo enviado desde cualquier pantalla + notas de llamada, no-leidos por hilo, globo verde en el menu (poll 30s), marcar leido al abrir, enlaces a ficha y contrato
- **[ADAPTAR]** `06f04600` Clientes: columna Cuenta (Activo/Liquidado/Devuelto/Castigado) con filtro y Limpiar filtros; botones Devuelto/Castigar/Reactivar en el contrato (bitacora); CRM de carritos abandonados (foto del carrito de clientes con sesion) con WhatsApp y descarte
- **[ADAPTAR]** `cb8d41d3` Cuenta del cliente (Clientes): solo contratos ENTREGADOS (activos o liquidados); antes de la entrega cada compra vive en su etapa: CRM sin pago, Ordenes en proceso
- **[ADAPTAR]** `296e0610` Estado del ciclo de vida por contrato (Mi cuenta): pago inicial pendiente / informacion incompleta / pendiente de aprobacion / pendiente de firma / pendiente de entrega / activo / liquidado; expediente completo exige comprador + 4 referencias (con 3 guardadas sigue incompleto)
- **[ADAPTAR]** `20a5e4f5` Cliente aprobado que regresa: reutiliza comprador/referencias verificados (auto si <6 meses; confirmar o editar si >6) con copia POR ORDEN (candado); referencias editables y ampliables en la verificacion; menu: Contratos bajo Clientes y zona de admin (Creditos/Catalogos/Riesgo/Config/Seguridad) solo master-admin-sistema
- **[ADAPTAR]** `e3db45d6` Firmas de administradores (4) para cambios sensibles: tasas, documentos legales y revocar acceso del equipo (rol sistema aplica directo; correo a cada admin para firmar; todo queda guardado y en la bitacora) + nuevas posiciones Gerente, Administrador de cuentas y Administrador de Redes sociales

**Tienda (`www-acasa-main`)**

- **[ADAPTAR]** `d4118f2f2` Perfil: selector de lada en el numero celular (EE.UU. sin +1 porque WhatsApp la agrega; +52 y otras explicitas)
- **[CORE]** `47324d12c` Perfil: guardar cambios refresca al usuario desde la API sin tocar la sesion (antes borraba el token JWT y la cuenta quedaba deslogueada: parecia que no guardaba)
- **[REVISAR]** `d2a1a63c0` Carrito: reportar la foto del carrito de clientes con sesion al backend (CRM de carritos abandonados); vacio o compra concretada la borra
- **[ADAPTAR]** `5d2368e72` Cliente: Ordenes muestra solo compras EN PROCESO; los contratos entregados (Activo/Liquidado) viven en Mi cuenta
- **[ADAPTAR]** `3f11dedb6` Mis ordenes: estado del ciclo de vida en cada contrato (pago inicial pendiente, informacion incompleta, pendiente de aprobacion, firma, entrega, activo, liquidado) + chip en el detalle; boton Tomar foto (camara del telefono) para identificacion y comprobantes
- **[REVISAR]** `4fcbbca59` Cliente que regresa: tarjeta Confirma tus datos (>6 meses) con Todo esta correcto / Necesito actualizar algo; formularios de datos prellenados con la informacion ya guardada

### 2026-08-05

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `f6cd4006` Bitacora de auditoria: quien hizo que (tasas, pagos, aprobaciones, firmas, entregas, eliminaciones) + pestana en Seguridad
- **[ADAPTAR]** `b46a4412` Herramienta de PRUEBAS en el contrato: mover el proximo vencimiento (desplaza las cuotas pendientes) para simular atrasos, vencidos y moratorios y construir cobranza
- **[ADAPTAR]** `f0dae67e` Tasa anual y CAT CALCULADOS por contrato: tasa = interes/principal anualizada por plazo (sin waiver); CAT = TIR efectiva de los flujos reales incluyendo la cuota de procesamiento vigente (sin seguro opcional); la caratula y el Anexo A se llenan solos y son dinamicos ante cambios de la cuota
- **[ADAPTAR]** `ad36be4a` Tasas: Moratorios (acumulan sobre vencidos desde el 2o dia, tasa/360 x dia, se cobran con el vencido), Cuota de procesamiento (se cobra en el pago inicial) y CAT informativo; los tres van a la caratula del contrato
- **[MX]** `8d2c890f` Seguridad > Tasas e impuestos: IVA, tasa de interes (define factor financiamiento 1+t/100 y factor contado 100/(100+t)) y waiver configurables; IVA se agrega a cada cobro Stripe y al Anexo A del contrato; waiver y factores dejan de estar fijos en codigo
- **[CORE]** `ba1899f8` Registrar pago (admin): selector Excedente a Plazo o a Saldo (acorta plazo y perdona interes)
- **[ADAPTAR]** `43177434` Sobrepago con eleccion PLAZO (adelanta cuotas) o SALDO (paga principal: acorta plazo y perdona el cargo financiero factor-1 sobre el excedente); tasa de interes = diferencia del factor a 100 (25%) visible en calendarios, resumen del contrato y en el documento para firma
- **[CORE]** `20e8970d` Expediente completo en el admin: copias del cliente (identificacion + comprobantes) por orden en la ficha y en la pantalla de verificacion
- **[ADAPTAR]** `fa70eb2a` Clientes: contratos desplegables bajo cada cliente con estado Activo/Inactivo; columna Cuenta (Activo/Inactivo) en la tabla de contratos y en la ficha
- **[ADAPTAR]** `ef2d3519` Ordenes = pipeline de trabajo: las compras con TODOS los articulos entregados salen de Ordenes y viven con el cliente (contratos activos y liquidados, pagos y notas)
- **[ADAPTAR]** `6ecf5075` Ficha: visor de la COPIA del contrato (texto fiel + firma, imprimir/PDF); contracts#show expone el expediente completo de la compra
- **[MX]** `08870b2c` Verificacion: comprador/aval/referencias/beneficiario se resuelven desde CUALQUIER orden hermana del contrato (los datos se capturan una vez por compra); alertas de CP usan los registros resueltos
- **[ADAPTAR]** `941200b1` Ficha del cliente: seccion Contratos y firmas (estado del documento, firmado por/fecha, ver imagen de la firma)
- **[ADAPTAR]** `19bed058` Firma: respaldo por CORREO del enlace (bilingue) cuando WhatsApp no esta disponible; notificacion de nueva orden ya NO manda emails a la agencia (usa NOTIFICATE_TO o clientes@acasamx.com)
- **[ADAPTAR]** `1e3f0d0c` Firma electronica del contrato: generar documento desde la plantilla legal (datos+tabla de pagos), WhatsApp con enlace de firma, endpoint sign (imagen a R2), boton en verificacion, y calendario del cliente visible hasta completar datos
- **[ADAPTAR]** `93757647` Pedidos sin pago inicial: fuera de Gestion de Contratos (solo CRM); el cliente puede CANCELAR su pedido no pagado (borra intento completo y restaura el principal de credito)
- **[CORE]** `dac45296` Migracion: contracts.contract_number acepta NULL (el numero se asigna al recibir el pago inicial)
- **[ADAPTAR]** `58330a05` Una compra = UNA orden (articulos del contrato agrupados en Ordenes, verificacion/aprobacion aplican a toda la compra, entrega por articulo); numero de CONTRATO se asigna al recibir el pago inicial, antes solo numero de pedido PED-
- **[ADAPTAR]** `e80506fe` Seguridad: la pestaña del contrato se llama Control de documentos legales
- **[ADAPTAR]** `4e0e03c9` Pipeline por pago: ordenes entran a Ordenes solo con pago inicial recibido; CRM de ventas por cerrar (intentos sin pago, WhatsApp + eliminar/liberar credito); cliente no ve calendario hasta pagar
- **[CORE]** `3cda7c9f` Ordenes: columna Enganche (alto rojo = sin pago inicial, $ verde = pagado) via downpayment_paid en el serializer
- **[ADAPTAR]** `bb845a3a` Seguridad: pestaña Contrato de credito con plantilla editable (texto completo VFF06072026 con campos {{auto}}, guardado en BD, restaurar original)
- **[REVISAR]** `7a690c52` Photo-only refresh script: re-descarga fotos por ASIN a R2 sin tocar precios
- **[ADAPTAR]** `4af1c05f` Backend root redirects to www.acasamx.com (removes leftover static landing that looked like the old site)
- **[ADAPTAR]** `fa2cc562` Admin: ficha completa del cliente (nombre como encabezado + boton Ficha) y popup de conversaciones por persona (bitacora de llamadas + WhatsApp) en verificacion de ordenes, clientes y pantalla del cliente

**Tienda (`www-acasa-main`)**

- **[CORE]** `93f0913da` Pago inicial cobra la cuota de procesamiento; pagos vencidos cobran y muestran intereses moratorios
- **[MX]** `a148994c0` Tienda usa tasas vivas del API (factor financiamiento/contado, waiver) y muestra/cobra IVA en pago inicial y pagos
- **[REVISAR]** `45686d1ea` Pagar: eleccion plazo/saldo al sobrepagar (saldo acorta plazo y ahorra el interes 25%); tasa visible en el calendario del cliente
- **[ADAPTAR]** `c74fc06d4` Mi expediente en la cuenta del cliente (datos, referencias, documentos, contrato por compra) y copia fiel del contrato firmado con imprimir/PDF
- **[ADAPTAR]** `41df7d6d7` Pagina de firma del contrato (lienzo dedo/mouse) + gates: completar datos antes del calendario, banner de firma pendiente
- **[CORE]** `0f6d00087` Boton Cancelar pedido en la pantalla de pedido reservado (solo antes del pago inicial)
- **[MX]** `83ea247c9` Checkout: login regresa al carrito (?next=), no rebotar a login mientras la sesion carga, y el formulario de beneficiario se cierra al guardar
- **[ADAPTAR]** `78f85946f` Cliente ve 'Pedido PED-x' hasta pagar el pago inicial; el numero de contrato aparece al pagar
- **[ADAPTAR]** `14dbfb9d5` Contrato del cliente: sin calendario de pagos hasta realizar el pago inicial (aviso Pedido reservado + boton al pago inicial)
- **[REVISAR]** `2a2ef11b8` Cart button: move from bottom-right to top-right, just under the fixed header
- **[REVISAR]** `de53ea185` Footer copyright reads exactly: (c) <year> Otthon Group, SAPI de CV, Todos los derechos reservados
- **[REVISAR]** `a8ad5c378` Footer: append legal line 'Otthon Group, SAPI de CV, Todos los derechos reservados' next to copyright, same font/style, both layouts
- **[CORE]** `c81f32d3c` Point /admin redirects at OUR backend (acasa-web.onrender.com) instead of the agency's rnzr service

### 2026-08-04

**Backend y back office (`ACACA_CODE`)**

- **[MX]** `1e7d0449` DB rebuild kit: catalog backup JSON + restore script (categories, FX, risk versions, products re-imported by ASIN via Rainforest with backup pricing overlaid)
- **[REVISAR]** `b67157d5` SAFETY: disable render.yaml (renamed .disabled) — Blueprint etl-space was re-syncing infrastructure on pushes and recreated the database; infra is now managed only via the Render dashboard
- **[CORE]** `6b701489` Show exact SMTP error class+message in password-link failure alert (admin-only)
- **[ADAPTAR]** `68baf627` Restore files silently reverted by stale-index commits: passwords controller + reset email templates + mailer method, ZipLookup service + order address alerts, passwords/send_password_setup routes
- **[REVISAR]** `79a0c29e` Password-link sending reports the truth: 422 when no email or SMTP fails; create shows warning
- **[CORE]** `fe0b27ef` Back office Seguridad: team user management; users create own passwords via emailed link; gated user create/update
- **[CORE]** `924d3e48` Delete customer: cascades contracts and orders; delivered contracts require admin credentials
- **[CORE]** `35c22687` Address alert: flag when buyer ZIP (US) or beneficiary CP (MX) does not match entered city/state, checked against real postal data (zip_codes cache + zippopotam.us); red warning boxes in admin order verification
- **[REVISAR]** `1b61cdf4` Password recovery: POST /api/passwords/forgot (email link, 2h validity, no user enumeration) + /reset; bilingual ES/EN reset email (US-English wording)
- **[REVISAR]** `ef384950` CORS: allow acasamx.com + www.acasamx.com (custom domain on Vercel)

**Tienda (`www-acasa-main`)**

- **[REVISAR]** `e361160c8` Login: friendly 401 message + password recovery link; /recuperar + /restablecer pages
- **[REVISAR]** `277b6a45a` Cart plan tiles + summary show the exact final payment (mirrors backend amortization: n-1 rounded installments, last = exact remainder)
- **[REVISAR]** `21c3a1361` Product detail pricing card: same math as cart (contado base, x1.25, tier minimums 20/10, special $10 plan) so Desde always equals lowest shown plan; legacy Lo quiero flow removed
- **[CORE]** `2c644061f` Cart: plans reflect chosen frequency (N pagos semanales/quincenales/mensuales), full recalc on item add/remove, drawer Desde weekly total, Seguir comprando returns to catalog, scroll-to-top on every navigation
- **[REVISAR]** `21cf7b18d` Show lowest weekly payment (Desde $X /semana) on product detail header and per-item in cart drawer + cart page
- **[REVISAR]** `644550e70` Product detail always opens scrolled to top (re-scroll after data load; browser was keeping prior scroll position)
- **[ADAPTAR]** `eeaf6b412` Landing: exact promo band (arrow pattern from Figma export, measured type scale, 50% white boxes) + exact product carousel (full-bleed snap-center, 400px cards, dots, auto-advance)
- **[ADAPTAR]** `7ec06620e` Landing: measured Figma geometry — 88% container (6vw margins @1920), H1 64px scale, heading 40px, HASTA 90px, hero rhythm per 1032px section
- **[ADAPTAR]** `8f0e89d56` Landing: photo cluster uses exact composite geometry (EUA 52.9%, MX 66.2% @39%) so the crossing arrow lines up
- **[ADAPTAR]** `d58f3275e` Landing: hero photo geometry per design — EUA 64% top-left, MX 63% offset 38% down-right, fixed cluster aspect
- **[ADAPTAR]** `958ed1db1` Landing: location tags straddle photo corners (like design); final subtitle copy 'De todo para todos'
- **[ADAPTAR]** `50cc17a51` Landing: exact Figma palette (sampled from design pixels) — hero gradient 1C266B/212E82/2B3A9C, orange FF7517, amber FFA607, pills 44509A, navbar 293797
- **[ADAPTAR]** `ca5ab5d1e` Landing: white SVG location pin in ESTADOS UNIDOS / MÉXICO tags (per Figma)
- **[ADAPTAR]** `10d3e06f5` Landing: ENVÍA BIENESTAR in golden amber per Figma
- **[ADAPTAR]** `2f368990f` Landing polish: navbar always solid navy rounded bar; hero badge as flush-left white tab (desktop) per Figma
- **[ADAPTAR]** `18c96715c` Landing: trust chips sit on white below the hero (per Figma)
- **[ADAPTAR]** `09d8f2648` Landing: blue hero runs to the very top (no white band) — navbar floats over blue like the Figma
- **[ADAPTAR]** `90189411f` Landing: hero photos (cropped from Figma export)
- **[ADAPTAR]** `bb18b29d6` Landing page from Figma (ACASA-LANDING): hero, trust chips, 40% countdown, live product carousel, 3 steps, promos, credit lead form, closing CTA — responsive per mobile frames; old CMS home kept as index.js.cms-backup

### 2026-08-03

**Backend y back office (`ACACA_CODE`)**

- **[REVISAR]** `a613b3ed` ActiveJob inline (no Sidekiq worker on Render): Active Storage purges actually delete files from R2
- **[REVISAR]** `f618eee2` Delete customer now also deletes their orders (cascades buyer/guarantor/references) — full cleanup for testing

**Tienda (`www-acasa-main`)**

- **[REVISAR]** `bab9c4e02` Click opens product detail; pill = lowest weekly payment, auto-size font
- **[REVISAR]** `afab1fafb` Cart drawer: layer above header (z-9999) and slightly narrower
- **[REVISAR]** `ef2a71110` Mini-cart drawer: slides in from the right on add-to-cart — items, contado total, Seguir comprando / Finalizar compra; floating button opens drawer
- **[CORE]** `41db3558b` Calendario de pagos: add Fecha de pago column (date each installment was paid) alongside amount paid

### 2026-08-02

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `176d5f5b` Autopay: customer opt-in per contract (requires saved card), daily engine charges due+past-due on saved card off-session (idempotent), secured /autopay/run endpoint for cron, admin badge
- **[CORE]** `480f6ef4` Stripe: clearer note for non-amortized charges (enganche/seguro)
- **[ADAPTAR]** `76f47698` WhatsApp: archive ALL inbound messages + photos (downloaded to R2) on the customer record; staff chat panel (send + conversation) from Órdenes rows and verification screen
- **[CORE]** `1481c6a4` Fix: delete customer (contracts cascade, staff-only); Estado 'Pre-aprobado' until admin verification; dashboard tabs reflect Pre-aprobado under Pendiente and true Aprobado
- **[ADAPTAR]** `c73d9b91` Order verification workflow: click order → review beneficiary/buyer(ID)/references w/ comment + verified per section; approve unlocks Amazon purchase; Pendiente → Por entregar → Entregado (confirm delivery); fulfillment pills on Órdenes + Contratos
- **[CORE]** `1dcff0c1` Stripe backend (REST, no gem): customers + saved cards, PaymentIntents w/ setup_future_usage, charge saved card off-session, finalize + webhook (idempotent payment recording)
- **[CORE]** `e24259a7` Admin Órdenes: fetch ALL orders (was paginated to first page — new orders invisible), newest first; Amazon purchase links on orders + contract items (Comprar en Amazon)
- **[REVISAR]** `47d32930` Contracts: waiver flag at create (10% stamped on orders); serializer exposes waiver + first_order_id
- **[REVISAR]** `05757c74` OrderSerializer: expose contract_id + contract_number for grouping in customer views
- **[REVISAR]** `593ff3ac` Credit caps the PRINCIPAL (cash - down); x1.25 is the finance charge on repayment. Min down = 10% + what credit can't cover
- **[CORE]** `eeaa9177` Pricing model: Total = cost x turns; cash price = x factor; financed = (cash - down) x 1.25; cash sale creates paid contract; admin math updated
- **[REVISAR]** `f3fca247` Contracts: accept beneficiary_id at create (validated as client's own), stamped on each order
- **[REVISAR]** `f516c85d` Security: clients only see/pay their OWN contracts; GET /api/users staff-only; record_payment allowed for contract owner (fixes cart initial payment)
- **[REVISAR]** `fe3e388a` Account Aging: Roll = accounts crossing into each bucket tonight (due today → 1-7; exactly 7/14/30/60 dpd → next bucket); Open Pct = past-due pct + due-today potential
- **[REVISAR]** `283e92aa` Account Aging: Roll/Open Pct row — current contracts due within each forward window; Total = past-due pct + due-this-week pct (combined exposure)
- **[ADAPTAR]** `2872d0ee` Gestión de Contratos: company totals bar (active/current/past-due/% /balances), Próximo Venc. column w/ days late, Account Aging page (1-7/8-14/15-30/31-60/61+ buckets, counts+pct, float $+pct)
- **[CORE]** `122433eb` Clientes: column order Crédito Autorizado → Utilizado → Disponible
- **[CORE]** `944984e7` Clientes/Créditos: rename columns to Crédito Autorizado / Crédito Disponible / Crédito Utilizado (utilizado = autorizado - disponible); headers wrap
- **[REVISAR]** `74943c02` Short plans: fixed $10/wk with reduced weeks when 3-month term can't reach $10 — last week pays remaining balance; catalog shows Desde $10
- **[REVISAR]** `e312bad8` Pricing: tiered weekly minimum — $10/wk for terms of 3 months or less, $20/wk for longer terms
- **[ADAPTAR]** `d7a9a10d` Contracts: delete a contract (restores pending credit) — 'Eliminar contrato' in drill-down + DELETE /contracts/:id, for cleaning up test data
- **[REVISAR]** `60d1cde9` Testing: set-credit tool (staff sets a client's credit line, overriding risk engine) — $ button on Clientes + POST /users/:id/set_credit
- **[REVISAR]** `d11b187a` Contracts: payment frequency (weekly/biweekly/monthly), Saturday/1st-aligned amortization, initial_payment = downpayment + first full period
- **[REVISAR]** `3dbbce3e` Contracts: back-dateable start_date (past-due testing), past_due_amount + next_due_date for reporting, optional payment date
- **[CORE]** `9a273143` Clientes: per-customer 'Recalcular' button applies active risk version to that account (complements all/selected on Motor de Riesgo)
- **[REVISAR]** `80fae86b` Contracts: clients can create their own combined contract; $20 minimum applies to the COMBINED weekly, not per item
- **[ADAPTAR]** `e527ae90` Risk: apply active version to all/selected customers (recalc credit, respects used); Contratos: multi-item cart builder
- **[REVISAR]** `b3e170cc` Catalog: scraped/imported products publish as active; JSON upload is additive (no mass-deactivate)
- **[ADAPTAR]** `fd18e3c8` Admin: Gestion de Contratos page (list, drill-down, amortization, record payment) + clickable client names
- **[CORE]** `82ef87a9` Contracts API (list/detail/create/record-payment) + full names on all admin sheets

**Tienda (`www-acasa-main`)**

- **[CORE]** `b28f1bce4` Contract page: Pagos automáticos toggle (activate/deactivate autopay with saved card)
- **[CORE]** `9cc1a02b6` Stripe frontend: card form (Payment Element via script tag) on pago-inicial + pagar, saved-card one-click, card saved for future payments; graceful fallback while keys absent
- **[ADAPTAR]** `2591ef7ba` Mi cuenta: customer landing page (credit status, contracts, past-due alert) + Hacer un pago page (next/past-due/payoff/custom + waiver); nav links point to /cuenta
- **[CORE]** `27572c3b5` Checkout flow: Continuar al pago inicial → pago-inicial page (enganche + primer pago + seguro 10% del pago, opt-out) → datos page (comprador + referencias); waiver flag sent at create
- **[ADAPTAR]** `a99e7679c` Customer contract detail page (/contratos/:id): summary, past-due alert, items, payment calendar; contract cards in Órdenes are clickable
- **[CORE]** `c1131ed9c` Customer Órdenes: contracts show as ONE card (contract number, items inside, combined payment, saldo, next due); standalone orders unchanged
- **[CORE]** `021b22d46` Cart: Crédito disponible row always visible — amount when logged in, 'Inicia sesión' link when not
- **[REVISAR]** `6d53755ce` Cart: credit floor = cash - credit (principal-based); insufficient check on principal
- **[REVISAR]** `cdc1733d9` Hide Total (internal calc): cart and product page show Precio de contado only
- **[REVISAR]** `b6cc31463` Cart: 'A financiar' label without formula disclaimer
- **[REVISAR]** `c44c40353` Cart/product page: show Total + Precio de contado, 'Pagar de contado' checkbox (paid cash sale), financed = (cash - down) x 1.25, credit floor uses /1.25
- **[REVISAR]** `5a9f46dda` Cart checkout: beneficiary step — pick or add (reuses BeneficiarySelection/Form), required before creating the contract
- **[REVISAR]** `bc59544a2` Cart: special reduced-week plan at fixed $10/wk (last payment covers remainder) when no standard term qualifies
- **[REVISAR]** `1255b1a0f` Cart: tiered weekly minimum ($10/wk at ≤3 months, $20/wk beyond); term filter uses weekly rate
- **[REVISAR]** `ec47a5729` Cart checkout: choose pay frequency (weekly/biweekly/monthly), see per-period payment, first due date (Sat/1st), and initial payment (enganche + first period); creates contract with frequency and records the initial payment
- **[REVISAR]** `1332ccfb9` Cart: enganche minimum = 10% of total + amount over available credit (per business rule)
- **[REVISAR]** `6094c37dd` Cart: enganche auto-defaults to max(10%, total-credit) like before; slider starts there; value shown as formatted currency
- **[REVISAR]** `11a9071ee` Catalog: selecting a product adds it to the cart and opens the cart; cart uses exact total_price
- **[REVISAR]** `306c634ce` Cart: default enganche to 10% (plans now show), down-payment slider, clearer credit warning; product page: remove single-item '¡Lo quiero!' flow (cart is the checkout)
- **[REVISAR]** `be29dc83f` Cart: add 'Seguir comprando' buttons (persistent + when no plan meets $20/wk) so users can add more items
- **[CORE]** `94ef3ea37` Producto: open at top (photo) on select; 'Más detalles' scrolls smoothly without leaving a #detalles hash
- **[REVISAR]** `acae92cbc` Cart: bundle items into one contract so the $20/week minimum applies to the cart total (CartContext, /carrito, add-to-cart)
- **[CORE]** `97bb47eb0` Producto: render full details section (#detalles anchor) so 'Más detalles' link works

### 2026-08-01

**Backend y back office (`ACACA_CODE`)**

- **[REVISAR]** `a25b80ef` R2: disable extra SDK checksum (fixes InvalidRequest on upload)
- **[REVISAR]** `6abc4b1f` Download product images inline during scrape (no background worker needed)
- **[REVISAR]** `ba7a47a5` Fix: customer list resilient if contracts table not migrated yet; storage via env (S3/R2 ready)
- **[REVISAR]** `b7ba47dc` Contracts/payments/amortization foundation; credit line vs remaining; customer columns + full name
- **[CORE]** `7ec649ce` Admin catalog: Pago x sem = lowest valid weekly (matches storefront Desde), discount-aware
- **[ADAPTAR]** `7ab86a95` Signup: never let the WhatsApp token step block account creation
- **[CORE]** `a65dd547` Admin catalog: add Net Turns column (cash / cost)
- **[CORE]** `8052c164` Admin login: match customer login (white bg, pill button, card, fonts)
- **[CORE]** `36b948f7` Admin: storefront fonts on login, remove test hint, add Financiado column
- **[ADAPTAR]** `ac9b9e9f` WhatsApp inbound QR verification + welcome email + admin logo/SMTP fixes
- **[ADAPTAR]** `947d5078` Admin: match storefront branding (acasa logo, lowercase, Geist font, navy/orange)
- **[REVISAR]** `b4209e45` New pricing model (Total=cost x turns x factor); email+password auth; hardening; absolute image URLs
- **[REVISAR]** `fef0ddec` Hardening: lock CORS to real domains, prod log level=info, silence auth debug logging
- **[CORE]** `29119d97` Security: signup forces cliente role; admin-gate credit + catalog; lock order-update pricing

**Tienda (`www-acasa-main`)**

- **[REVISAR]** `78dbbfdf0` Signup: handle -credit case (no fake Aprobado)
- **[REVISAR]** `77eb01b99` Signup: real error messages + Approved/credit-amount screen; slider label back to Enganche
- **[CORE]** `48bcbf68a` Storefront: 'Rango de pagos' slider label, dedupe footer links
- **[ADAPTAR]** `dc11f7c69` Signup: WhatsApp QR verification + live polling
- **[REVISAR]** `c83eb2f5e` Signup: add password fields (required for new email+password login)
- **[CORE]** `e00cdfad2` Email+password login (token auth) + Total-based pricing display
- **[REVISAR]** `85e181253` Security: enable TLS certificate verification

### 2026-07-27

**Backend y back office (`ACACA_CODE`)**

- **[CORE]** `5010d68f` Admin: update back-to-store link to acasa-frontend.vercel.app
- **[REVISAR]** `5c997080` Add line-ending normalization; align working tree
- **[REVISAR]** `fe1d3118` product.rb: emit absolute image URLs in dev too (rails_blob_url) so the Next.js frontend on :3001 can load catalog photos
- **[REVISAR]** `8358ea4b` Update production.rb
- **[REVISAR]** `779603f4` Modify dockerCommand in render.yaml
- **[REVISAR]** `4cc4f297` Update Dockerfile for Ruby on Rails application
- **[REVISAR]** `7a2b8a93` Modify dockerCommand for acasa-web service
- **[REVISAR]** `567e7abf` Add dockerCommand to acasa-web service
- **[REVISAR]** `f5069714` Reformat render.yaml for consistency
- **[REVISAR]** `1260f232` Modify dockerCommand for acasa-web service
- **[REVISAR]** `7c8c453f` Remove comments and clean up render.yaml

**Tienda (`www-acasa-main`)**

- **[REVISAR]** `9dc594813` Storefront: category/subcategory catalog filter + branding
- **[CORE]** `9848c0447` Redirect /admin to Rails admin on Render; keep admin off public storefront

### 2026-07-24

**Backend y back office (`ACACA_CODE`)**

- **[REVISAR]** `dbbac4e3` changelog: log 2026-07-24 work (pricing fix, Modelo column, search upgrade)
- **[REVISAR]** `e250cff6` shop.html: storefront search matches every word across title/brand/model/keywords/category, accent-insensitive
- **[CORE]** `e20af21c` admin.html: add sortable Modelo (model_number) column to catalog table

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
