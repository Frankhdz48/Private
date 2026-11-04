# Volume Profile EA (MetaTrader 5)

Robot de trading (Expert Advisor) que opera solo dos estrategias basadas en el **Volume Profile de la sesión anterior**:

| # | Estrategia | Condición previa | Gatillo de entrada | Stop Loss | Take Profit |
|---|---|---|---|---|---|
| 1 | **POC Bounce** | La sesión anterior **cerró fuera** del Value Area | El precio vuelve al POC y forma una **vela envolvente** (engulfing) de rechazo | Un poco más allá del POC / de la mecha | `InpRR_POC` (2R por defecto, como en la guía) |
| 3 | **Breakout** | Ninguna (da igual dónde cerró) | Ruptura de VAH/VAL → **pullback** que no se mete mucho en el VA → **BOS** (rompe el último máximo/mínimo) | Más allá del extremo del pullback | `InpRR_Breakout` (3R por defecto) |

Archivo: [`MT5/Experts/VolumeProfileEA.mq5`](MT5/Experts/VolumeProfileEA.mq5)

---

## Cómo funciona por dentro

1. **Sesión**: cada día empieza a la hora `InpSessionStartHour` (hora del **servidor** del broker). Los fines de semana se saltan automáticamente.
2. **Volume Profile**: al iniciar cada sesión toma las velas M1 de la sesión anterior, reparte el volumen de cada vela entre su máximo y su mínimo, y calcula:
   - **POC**: el nivel con más volumen.
   - **Value Area (VAH / VAL)**: el rango que contiene el 70 % del volumen, expandiéndose desde el POC.
   - Dibuja las tres líneas en el gráfico.
3. **Cada vela cerrada de M15** (`InpEntryTF`) revisa las condiciones de las dos estrategias.
4. **Una sola posición a la vez** por símbolo; cada estrategia opera como máximo una vez por sesión y dirección.

> En forex se usa *tick volume* (el broker no da volumen real). En futuros/índices con volumen real activa `InpUseRealVolume`.

---

## Gestión de riesgo (incluida)

| Parámetro | Defecto | Para qué sirve |
|---|---|---|
| `InpRiskPercent` | 1 % | Calcula el lote solo para que, si toca el SL, pierdas exactamente ese % del balance. |
| `InpRR_POC` / `InpRR_Breakout` | 2 / 3 | Relación riesgo:beneficio de cada estrategia. |
| `InpMaxTradesPerSession` | 2 | Máximo de operaciones por día. |
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

- **POC Bounce → 1:2** (el objetivo natural suele ser volver al VAH/VAL, no está tan lejos).
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
   - Periodo: mínimo 2 años. Símbolos sugeridos para empezar: `US500`, `NAS100`, `EURUSD`, `XAUUSD`.
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
- [x] **Paso 5** — Gestión de riesgo: lote por %, R:R, límites diarios, breakeven.
- [ ] **Paso 6** — Compilar en MetaEditor y corregir errores (lo haces tú y me pasas el log).
- [ ] **Paso 7** — Backtest + optimización + forward test; ajustar reglas según resultados.
- [ ] **Paso 8** — Extras: filtro de noticias, trailing stop, Estrategia #2 (si me pasas la imagen), alertas al celular (push notifications).
- [ ] **Paso 9** — Demo → real pequeña → VPS.
- [ ] **(Opcional)** Versión MT4 si tu broker solo ofrece MT4.

---

⚠️ **Aviso**: ningún robot garantiza ganancias. Esta estrategia viene de una guía de redes sociales y no tiene resultados verificados; el backtest es lo que dirá si tiene ventaja real. No operes en real con dinero que no puedas perder.
