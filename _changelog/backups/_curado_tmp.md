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

