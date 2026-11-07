# Volume Profile EA (MetaTrader 5)

Robot de trading (Expert Advisor) que opera las **3 estrategias del "Volume Profile Trading Blueprint"** como **un solo sistema**, usando el Volume Profile de la **sesión anterior**.

Archivo: [`MT5/Experts/VolumeProfileEA.mq5`](MT5/Experts/VolumeProfileEA.mq5)

---

## Resumen de la estrategia

### Los niveles (se calculan solos cada día)
Igual que el *Fixed Range Volume Profile* de TradingView puesto sobre **toda la sesión de ayer** (Row Size 60, Value Area 70 %), con los niveles extendidos a la sesión de hoy:

- **POC** (Point of Control): el precio con más volumen → soporte/resistencia.
- **VAH / VAL**: límites del Value Area (70 % del volumen).
  - Debajo del VAL = **descuento** → el precio tiende a subir.
  - Arriba del VAH = **premium** → el precio tiende a bajar.

### ¿Qué estrategia aplica? (depende de cómo cerró ayer y de lo que hace el precio hoy)

| # | Estrategia | Ayer cerró… | Qué espera hoy | Entrada | Stop Loss | TP |
|---|---|---|---|---|---|---|
| 1 | **POC Bounce** | **FUERA** del VA | El precio regresa al POC | Vela de rechazo en el POC (envolvente o pin bar) a favor del rebote | Un poco más allá del POC / mecha | 2R |
| 2 | **VA Reversal** | **DENTRO** del VA | El precio sale arriba del VAH o abajo del VAL | Una vela **cierra** de vuelta dentro del VA (las mechas no cuentan) | Detrás del swing que hizo fuera | 2R |
| 3 | **Breakout** | Da igual | El precio rompe VAH/VAL, hace pullback sin meterse mucho y aguanta | Break of Structure: nuevo máximo (alcista) / nuevo mínimo (bajista) | Detrás del pullback | 2R* |

\* La guía no da objetivo para el Breakout. En los días revisados de oro 2R funcionó mejor que 3R; se ajusta en el backtest.

La guía permite repetir la Reversal en la misma sesión; el robot la limita a **1 por lado del VA por sesión** (`InpRevMaxPerSide`) para evitar señales repetidas cuando el precio da vueltas en el VAH/VAL.

---

## Cómo funciona por dentro

### El Volume Profile lo calcula y lo dibuja el robot (no hace falta TradingView)
Al empezar cada sesión, el EA hace lo mismo que la guía hace a mano con el *Fixed Range Volume Profile*:

| Paso de la guía | Lo que hace el EA |
|---|---|
| Usar temporalidad intradía | Construye el perfil con velas de **1 minuto** (máxima precisión) y opera en **M15** |
| Poner el FRVP sobre toda la sesión de ayer | Toma todas las velas M1 de la sesión anterior (salta fines de semana) |
| Row Size 60 | Divide el rango de ayer en **60 filas** y reparte el volumen de cada vela entre su máximo y mínimo |
| Value Area 70 % | Desde el POC suma filas hacia el lado con más volumen hasta juntar el **70 %** |
| VAH, VAL y POC visibles, POC en rojo | Dibuja el **histograma** (azul = dentro del VA, gris = fuera, rojo = POC) y las líneas POC/VAH/VAL |
| Extender los niveles al día actual | Las líneas se extienden a la sesión siguiente, que es donde se usan |

Dibuja las últimas 5 sesiones (`InpDrawSessions`) para que lo compares contra TradingView.

### Funcionamiento
1. **Sesión**: cada día empieza a la hora `InpSessionStartHour` (hora del **servidor** del broker).
2. **Cada vela cerrada de M15** (`InpEntryTF`) revisa las tres estrategias, la detección de tendencia y los filtros.
3. **Una sola posición a la vez** por símbolo.

### Breakout: qué cuenta como pullback (`InpBOPullbackMode`)
- **Zona VA**: el precio regresa a 0.5 ATR del VAH/VAL (estricto, como la guía). Menos operaciones; se pierde los días de tendencia fuerte.
- **Impulso**: el precio retrocede al menos 38.2 % del movimiento de ruptura (que debe medir ≥ 1 ATR).
- **Cualquiera** (defecto): vale cualquiera de las dos.

### Breakout cuando la sesión abre ya fuera del VA (`InpBOOpenOutside`)
- **Ignorar**: solo cuenta una ruptura real (una vela que venía de adentro y cierra afuera).
- **Exigir retest** (defecto): cuenta, pero el pullback tiene que volver al borde del VA (VAH/VAL), como el 6 nov.
- **Normal**: cuenta como cualquier ruptura.

### Día de tendencia
Tres señales medibles, se necesitan 2 (`InpTrendMinScore`):
1. El precio cierra a más de **2 ATR** fuera del VA.
2. **ADX ≥ 25** con el DI a favor.
3. El VA de ayer fue **angosto** (< 0.5 × ATR diario): compresión antes de expansión.

Cuando se detecta: **bloquea entradas en contra** (`InpTrendBlockCounter`) y las entradas **a favor van sin TP** con trailing (`InpTrendRunner`). Termina cuando una vela cierra de vuelta dentro del VA.

### Filtro de noticias
Usa el **calendario económico integrado de MT5**: no abre operaciones 30 min antes ni 30 min después de noticias de **alto impacto** del USD (y XAU). Las posiciones abiertas no se tocan.
> ⚠️ El calendario **no funciona en el Probador de Estrategias**: en el backtest el filtro queda apagado; solo actúa en demo/real.

### Cómo traduje lo "a ojo" de la guía a reglas exactas

| La guía dice… | El robot usa… | Parámetro |
|---|---|---|
| "price touches the POC" | El mínimo/máximo llega a ±0.25 ATR del POC sin perforarlo más de 0.5 ATR | `InpPOCTouchATR`, `InpPOCMaxPierceATR` |
| "signs of rejection" | Envolvente o pin bar | `InpPOCAllowPinBar` |
| "price moves outside the VA" (Reversal) | Una vela cierra fuera del VA | `InpRevRequireCloseOutside` |
| "stop near the recent swing" | Extremo alcanzado fuera del VA + colchón | `InpSLBufferATR` |
| "pullback and hold near the VA" | El precio vuelve a 0.5 ATR del VAH/VAL | `InpBOPullbackATR` |
| "should not move too deep back inside" | No cierra más de 30 % dentro del VA | `InpBOMaxDepthPct` |
| "Break of Structure" | Cierre por encima del máximo (o debajo del mínimo) previo al pullback | — |

> En forex/oro se usa *tick volume* (igual que TradingView con OANDA). En futuros con volumen real activa `InpUseRealVolume`.

---

## Gestión de riesgo (incluida)

| Parámetro | Defecto | Para qué sirve |
|---|---|---|
| `InpRiskPercent` | 1 % | Calcula el lote solo para que, si toca el SL, pierdas exactamente ese % del balance. |
| `InpMaxRiskPctMinLot` | 100 % | En cuentas pequeñas el lote mínimo (0.01) puede arriesgar mucho más que `InpRiskPercent`. Con 100 opera igual; bájalo (ej. 10) para que no opere si el lote mínimo arriesga más de eso. |
| `InpRR_POC` / `InpRR_Reversal` / `InpRR_Breakout` | 2 / 2 / 2 | Relación riesgo:beneficio de cada estrategia. |
| `InpMaxTradesPerSession` | 3 | Máximo de operaciones por día. |
| `InpMaxDailyLossPct` | 3 % | Si pierdes esto en el día, el robot deja de operar hasta la siguiente sesión. |
| `InpMaxConsecLosses` | 2 | Tras 2 pérdidas seguidas, se detiene ese día. |
| `InpUseBreakeven` / `InpBreakevenAtR` | sí / 1R | Cuando va ganando 1R, mueve el SL a la entrada (operación "sin riesgo"). |
| `InpMaxSLATR` | 3 ATR | Ignora señales con stops demasiado grandes. |

### Cierre parcial
Con `InpUsePartial` activo, al llegar a **2R** cierra el **50 %** y el resto sigue con el stop en breakeven y trailing, sin TP (`InpRunnerTP_R = 0`).
Si el lote no se puede partir (con 0.01 lote, p. ej. cuentas de 50 USD) la operación se maneja normal, con su TP.

### Trailing stop

Una vez que la operación avanza `InpTrailStartR` (1R por defecto), el stop empieza a seguir al precio. **Solo se mueve a favor, nunca hacia atrás.**

| Modo (`InpTrailMode`) | Cómo mueve el stop | Ideal para |
|---|---|---|
| `TRAIL_OFF` | No hace trailing (solo breakeven si está activado) | Comparar en el backtest |
| `TRAIL_ATR` (defecto) | Siempre a 1.5 ATR del precio (`InpTrailATRMult`) | Uso general |
| `TRAIL_SWING` | Debajo del mínimo (compras) / encima del máximo (ventas) de las últimas 3 velas | Tendencias limpias |
| `TRAIL_STEP` | Escalonado: al llegar a 2R asegura 1R, a 3R asegura 2R… | Asegurar ganancias por escalones |

`InpTrailNoTP = true` quita el Take Profit y deja que **el trailing cierre la operación**: atrapa días de tendencia (como el 30 oct en oro, que cayó 150 USD) a cambio de devolver algo de ganancia en los días normales. Pruébalo contra el TP fijo en el backtest.

| `InpMaxSpreadPoints` | 0 (off) | No entra si el spread está muy abierto (noticias, apertura). |

### ¿1:2 o 1:3? — Lo que dicen los números

El *win rate* mínimo para no perder dinero es `1 / (1 + R)`:

| R:R | Win rate mínimo para empatar | Con 40 % de aciertos (100 trades, 1 % riesgo) |
|---|---|---|
| 1:1 | 50 % | −20 % |
| 1:2 | 33 % | **+20 %** |
| 1:3 | 25 % | **+60 %** |

Pero **más R:R = menos aciertos**, porque el precio tiene que viajar más lejos. Por eso no se elige a ojo: se prueba en el backtest. Mi recomendación para empezar:

- **POC Bounce y Reversal → 1:2** (lo que dice la guía; son de regreso a la media y el objetivo natural está cerca).
- **Breakout → 1:3** (las rupturas con continuación sí recorren más).
- **Riesgo 0.5 %–1 % por operación**. Con 1 %, 10 pérdidas seguidas (pasa) son ~−10 %, recuperable.

---

## Instalación

1. Abre MetaTrader 5 → **Archivo → Abrir carpeta de datos**.
2. Copia `VolumeProfileEA.mq5` a `MQL5/Experts/`.
3. Abre MetaEditor (F4), abre el archivo y pulsa **Compilar** (F7). Si sale algún error, pásamelo y lo corrijo.
4. En MT5 arrastra el EA a un gráfico (el gráfico puede estar en cualquier temporalidad), activa **Trading algorítmico**.

## Probarlo antes de arriesgar dinero (obligatorio)

1. **Backtest** — Ver → Probador de estrategias:
   - Modelo: **"Cada tick basado en ticks reales"**.
   - Periodo: mínimo 2 años. Símbolos sugeridos: `XAUUSD` (el que usa la guía), `US500`, `NAS100`, `EURUSD`. La guía usa gráficos de 1H y 15m.
   - Revisa: factor de beneficio > 1.3, drawdown máximo < 15–20 %, mínimo ~100 operaciones.
2. **Optimización** — optimiza pocos parámetros a la vez (`InpRR_*`, `InpSessionStartHour`, `InpBOMaxDepthPct`, `InpPOCTouchATR`). Guarda el último 25–30 % del historial **sin optimizar** para validar (*forward test*) y evitar sobreajuste.
3. **Cuenta demo** 4–8 semanas.
4. **Cuenta real pequeña** con riesgo 0.25–0.5 %.

## Que corra 24/7 sin ti

El EA solo funciona mientras MT5 esté abierto y conectado. Opciones:

- **VPS integrado de MetaQuotes** (clic derecho en la cuenta → "Registrar un servidor virtual"), ~15 USD/mes, el más sencillo.
- Un **VPS Windows** (Contabo, ForexVPS, etc.) con MT5 instalado.
- Revisa el robot al menos una vez por semana (diario de la pestaña "Expertos").

---

## Checklist del proyecto

### ✅ Hecho
- [x] Reglas de la guía traducidas a reglas exactas y medibles
- [x] Volume Profile de la sesión anterior (POC, VAH, VAL, 60 filas, 70 %)
- [x] Estrategia #1 POC Bounce
- [x] Estrategia #2 Value Area Reversal
- [x] Estrategia #3 Breakout (ruptura → pullback → BOS)
- [x] Las 3 como un solo sistema (cada una según cómo cerró la sesión anterior)
- [x] Riesgo: lote por %, R:R, límites diarios, pérdidas seguidas, breakeven
- [x] Lote mínimo en cuentas pequeñas (`InpMaxRiskPctMinLot`) + revisión de margen
- [x] Trailing stop (ATR, swing, escalonado) y opción sin TP

- [x] Volume Profile calculado y **dibujado** por el EA (histograma + POC/VAH/VAL, últimas 5 sesiones)
- [x] Breakout: pullback por zona VA o por retroceso del impulso
- [x] Breakout: manejo de sesiones que abren fuera del VA (retest obligatorio)
- [x] Máx. 1 Reversal por lado del VA por sesión
- [x] Cierre parcial (50 % en 2R, resto con trailing)
- [x] Detección de día de tendencia (distancia al VA, ADX, VA angosto)
- [x] Filtro de noticias (calendario MT5)

### 🔧 Mejoras al código (pendientes)
- [ ] **Alertas al celular** (notificaciones push de MT5 al abrir/cerrar)
- [ ] **Versión MT4** (si tu broker solo ofrece MT4)

### 🧪 Pruebas (las haces tú, yo te ayudo a leer resultados)
- [ ] Compilar en MetaEditor (F7) y pasarme los errores
- [ ] Comparar las líneas POC/VAH/VAL del robot con TradingView en los mismos días
- [ ] Backtest XAUUSD 2+ años, "cada tick basado en ticks reales"
- [ ] Comparar variantes: TP fijo vs sin TP vs parcial; Breakout 2R vs 3R; cada estrategia por separado
- [ ] Optimizar pocos parámetros y validar en datos no usados (forward test)

### 🚀 Puesta en marcha
- [ ] Cuenta demo XM con el mismo saldo que usarás en real, 4–8 semanas
- [ ] Cuenta real pequeña
- [ ] VPS para que corra 24/7
- [ ] Revisión semanal del diario del robot

---

⚠️ **Aviso**: ningún robot garantiza ganancias. Esta estrategia viene de una guía de redes sociales y no tiene resultados verificados; el backtest es lo que dirá si tiene ventaja real. No operes en real con dinero que no puedas perder.
