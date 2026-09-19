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

