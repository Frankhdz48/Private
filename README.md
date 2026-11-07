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
| 3 | **Breakout** | Da igual | El precio rompe VAH/VAL, hace pullback sin meterse mucho y aguanta | Break of Structure: nuevo máximo (alcista) / nuevo mínimo (bajista) | Detrás del pullback | 3R* |

\* La guía no da objetivo para el Breakout; uso 3R porque las rupturas que continúan suelen recorrer más. Se ajusta en el backtest.

La Reversal **se puede repetir** varias veces en la misma sesión cada vez que el precio sale y vuelve a cerrar dentro (limitado por `InpMaxTradesPerSession`).

---

## Cómo funciona por dentro

1. **Sesión**: cada día empieza a la hora `InpSessionStartHour` (hora del **servidor** del broker). Los fines de semana se saltan automáticamente.
2. **Volume Profile**: al iniciar cada sesión toma las velas M1 de la sesión anterior, reparte el volumen de cada vela entre su máximo y su mínimo en 60 filas y calcula POC, VAH y VAL. Dibuja las líneas en el gráfico.
3. **Cada vela cerrada de M15** (`InpEntryTF`) revisa las tres estrategias.
4. **Una sola posición a la vez** por símbolo.

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
| `InpRR_POC` / `InpRR_Reversal` / `InpRR_Breakout` | 2 / 2 / 3 | Relación riesgo:beneficio de cada estrategia. |
| `InpMaxTradesPerSession` | 3 | Máximo de operaciones por día. |
| `InpMaxDailyLossPct` | 3 % | Si pierdes esto en el día, el robot deja de operar hasta la siguiente sesión. |
| `InpMaxConsecLosses` | 2 | Tras 2 pérdidas seguidas, se detiene ese día. |
| `InpUseBreakeven` / `InpBreakevenAtR` | sí / 1R | Cuando va ganando 1R, mueve el SL a la entrada (operación "sin riesgo"). |
| `InpMaxSLATR` | 3 ATR | Ignora señales con stops demasiado grandes. |
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

## Plan / hoja de ruta

- [x] **Paso 1** — Traducir las reglas de las imágenes a reglas exactas y medibles.
- [x] **Paso 2** — Cálculo del Volume Profile (POC, VAH, VAL) de la sesión anterior.
- [x] **Paso 3** — Estrategia #1 POC Bounce.
- [x] **Paso 4** — Estrategia #3 Breakout (ruptura → pullback → BOS).
- [x] **Paso 4b** — Estrategia #2 Value Area Reversal + las 3 como un solo sistema.
- [x] **Paso 5** — Gestión de riesgo: lote por %, R:R, límites diarios, breakeven.
- [ ] **Paso 6** — Compilar en MetaEditor y corregir errores (lo haces tú y me pasas el log).
- [ ] **Paso 7** — Backtest + optimización + forward test; ajustar reglas según resultados.
- [ ] **Paso 8** — Extras: filtro de noticias, trailing stop, alertas al celular (push notifications).
- [ ] **Paso 9** — Demo → real pequeña → VPS.
- [ ] **(Opcional)** Versión MT4 si tu broker solo ofrece MT4.

---

⚠️ **Aviso**: ningún robot garantiza ganancias. Esta estrategia viene de una guía de redes sociales y no tiene resultados verificados; el backtest es lo que dirá si tiene ventaja real. No operes en real con dinero que no puedas perder.
