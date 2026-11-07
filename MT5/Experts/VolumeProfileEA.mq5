//+------------------------------------------------------------------+
//|                                             VolumeProfileEA.mq5  |
//|                                                                  |
//|  El EA calcula SOLO el Volume Profile de la sesión anterior      |
//|  (equivalente al Fixed Range Volume Profile de TradingView sobre |
//|  la sesión completa de ayer: Row Size 60, Value Area 70 %), lo   |
//|  dibuja en el gráfico y opera el sistema completo:               |
//|                                                                  |
//|   #1 POC Bounce : la sesión anterior cerró FUERA del VA, el      |
//|                   precio vuelve al POC y lo rechaza.             |
//|   #2 VA Reversal: la sesión anterior cerró DENTRO del VA, el     |
//|                   precio sale y una vela CIERRA de vuelta dentro.|
//|   #3 Breakout   : rompe VAH/VAL, pullback, Break of Structure.   |
//+------------------------------------------------------------------+
#property copyright "frankhdz48"
#property version   "1.30"
#property description "POC Bounce + VA Reversal + VA Breakout (Volume Profile de la sesión anterior)"

#include <Trade/Trade.mqh>

//--- Enumeraciones de configuración --------------------------------
enum ENUM_TRAIL_MODE
  {
   TRAIL_OFF   = 0,   // Sin trailing
   TRAIL_ATR   = 1,   // Trailing por ATR (distancia fija en ATR)
   TRAIL_SWING = 2,   // Trailing por swing (mínimo/máximo de las últimas N velas)
   TRAIL_STEP  = 3    // Escalonado en R (asegura 1R al llegar a 2R, etc.)
  };

enum ENUM_BO_PULLBACK
  {
   PB_VA_ZONE = 0,    // Pullback solo cerca del VAH/VAL (estricto, como la guía)
   PB_IMPULSE = 1,    // Pullback = retroceso del % del impulso de ruptura
   PB_EITHER  = 2     // Cualquiera de los dos (recomendado)
  };

enum ENUM_BO_OPEN_OUTSIDE
  {
   OPEN_IGNORE = 0,   // Abrir fuera del VA NO cuenta como ruptura
   OPEN_RETEST = 1,   // Cuenta, pero exige retest al VAH/VAL (recomendado)
   OPEN_NORMAL = 2    // Cuenta como cualquier ruptura
  };

//--- Entradas -------------------------------------------------------
input group "=== Estrategias ==="
input bool   InpUsePOCBounce        = true;   // Activar Estrategia #1 POC Bounce
input bool   InpUseReversal         = true;   // Activar Estrategia #2 Value Area Reversal
input bool   InpUseBreakout         = true;   // Activar Estrategia #3 Breakout

input group "=== Sesión / Volume Profile (config. de la guía) ==="
input int    InpSessionStartHour    = 0;      // Hora de inicio de sesión (hora del SERVIDOR)
input int    InpSessionStartMinute  = 0;      // Minuto de inicio de sesión
input ENUM_TIMEFRAMES InpProfileTF  = PERIOD_M1; // Velas con las que se construye el perfil
input int    InpProfileBins         = 60;     // Row Size (filas del perfil) — guía: 60
input double InpValueAreaPct        = 70.0;   // Value Area Volume (%) — guía: 70
input bool   InpUseRealVolume       = false;  // Usar volumen real (futuros) en vez de tick volume
input int    InpMinSessionBars      = 60;     // Mínimo de velas para considerar una sesión válida

input group "=== Dibujo del Volume Profile ==="
input bool   InpDrawProfile         = true;   // Dibujar histograma + POC/VAH/VAL
input int    InpDrawSessions        = 5;      // Cuántas sesiones pasadas dibujar
input double InpHistWidthPct        = 35.0;   // Ancho del histograma (% de la sesión)
input color  InpColorVA             = C'40,120,170'; // Color filas dentro del VA
input color  InpColorOut            = C'70,70,80';   // Color filas fuera del VA
input color  InpColorPOC            = clrRed;        // Color POC
input color  InpColorVAEdges        = clrWhite;      // Color VAH / VAL

input group "=== Entradas ==="
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_M15; // Temporalidad de entrada (intradía)
input int    InpATRPeriod           = 14;     // Periodo ATR (para tolerancias)
input double InpSLBufferATR         = 0.20;   // Colchón del Stop Loss (x ATR)
input double InpMaxSLATR            = 3.0;    // Ignorar señales con SL mayor a X ATR
input int    InpTradeStartHour      = 0;      // Operar desde (hora servidor)
input int    InpTradeEndHour        = 24;     // Operar hasta (hora servidor)

input group "=== #1 POC Bounce ==="
input double InpPOCTouchATR         = 0.25;   // Tolerancia de "toque" al POC (x ATR)
input double InpPOCMaxPierceATR     = 0.50;   // Máximo que puede perforar el POC (x ATR)
input bool   InpPOCAllowPinBar      = true;   // Aceptar pin bar además de envolvente
input double InpRR_POC              = 2.0;    // R:R (guía: 2R)

input group "=== #2 Value Area Reversal ==="
input bool   InpRevRequireCloseOutside = true; // Exigir una vela CERRADA fuera del VA
input int    InpRevMaxPerSide       = 1;      // Máx. reversals por lado del VA por sesión (0 = sin límite)
input double InpRR_Reversal         = 2.0;    // R:R (guía: 2R)

input group "=== #3 Breakout ==="
input ENUM_BO_PULLBACK InpBOPullbackMode = PB_EITHER; // Qué cuenta como pullback
input double InpBOPullbackATR       = 0.50;   // Zona VA: distancia al VAH/VAL (x ATR)
input double InpBORetracePct        = 38.2;   // Impulso: % mínimo de retroceso
input double InpBOMinImpulseATR     = 1.0;    // Impulso: tamaño mínimo de la ruptura (x ATR)
input double InpBOMaxDepthPct       = 30.0;   // % máximo del VA que puede volver a entrar
input ENUM_BO_OPEN_OUTSIDE InpBOOpenOutside = OPEN_RETEST; // Si la sesión abre ya fuera del VA
input double InpRR_Breakout         = 2.0;    // R:R

input group "=== Detección de día de tendencia ==="
input bool   InpUseTrendDetect      = true;   // Activar detección de tendencia
input double InpTrendDistATR        = 2.0;    // Señal 1: precio a más de X ATR fuera del VA
input int    InpADXPeriod           = 14;     // Señal 2: periodo ADX
input double InpTrendADX            = 25.0;   // Señal 2: ADX mínimo (con DI a favor)
input double InpTrendNarrowVA       = 0.5;    // Señal 3: VA de ayer < X * ATR diario (VA angosto)
input int    InpTrendMinScore       = 2;      // Señales necesarias (de 3) para día de tendencia
input bool   InpTrendBlockCounter   = true;   // En tendencia: bloquear entradas en contra
input bool   InpTrendRunner         = true;   // En tendencia: entradas a favor sin TP (trailing)

input group "=== Gestión de riesgo ==="
input double InpRiskPercent         = 1.0;    // Riesgo por operación (% del balance)
input double InpMaxRiskPctMinLot    = 100.0;  // Lote mínimo permitido si arriesga <= X% (100 = siempre)
input int    InpMaxTradesPerSession = 3;      // Máx. operaciones por sesión
input double InpMaxDailyLossPct     = 3.0;    // Pérdida máxima diaria (%) -> se detiene
input int    InpMaxConsecLosses     = 2;      // Pérdidas seguidas -> se detiene la sesión (0 = off)
input bool   InpUseBreakeven        = true;   // Mover SL a breakeven
input double InpBreakevenAtR        = 1.0;    // ...cuando el precio avanza X R

input group "=== Cierre parcial ==="
input bool   InpUsePartial          = true;   // Cerrar una parte y dejar correr el resto
input double InpPartialAtR          = 2.0;    // Cerrar parcial al llegar a X R
input double InpPartialPct          = 50.0;   // % de la posición a cerrar
input double InpRunnerTP_R          = 0.0;    // TP del resto en R (0 = sin TP, lo cierra el trailing)

input group "=== Trailing stop ==="
input ENUM_TRAIL_MODE InpTrailMode  = TRAIL_ATR; // Tipo de trailing stop
input double InpTrailStartR         = 1.0;    // Activar trailing cuando el precio avanza X R
input double InpTrailATRMult        = 1.5;    // ATR: distancia del stop (x ATR)
input int    InpTrailSwingBars      = 3;      // Swing: velas cerradas a mirar
input double InpTrailStepR          = 1.0;    // Escalonado: cada X R de avance, sube el stop X R
input bool   InpTrailNoTP           = false;  // Sin Take Profit en TODAS las operaciones

input group "=== Filtro de noticias ==="
input bool   InpUseNewsFilter       = true;   // No abrir operaciones cerca de noticias de alto impacto
input int    InpNewsMinutesBefore   = 30;     // Minutos antes de la noticia
input int    InpNewsMinutesAfter    = 30;     // Minutos después de la noticia
input bool   InpNewsIncludeMedium   = false;  // Incluir también noticias de impacto medio

input group "=== Otros ==="
input bool   InpCloseAtSessionEnd   = false;  // Cerrar posiciones al terminar la sesión
input int    InpMaxSpreadPoints     = 0;      // Spread máximo en puntos (0 = sin filtro)
input long   InpMagic               = 48001;  // Número mágico

//--- Tipos ----------------------------------------------------------
struct Profile
  {
   bool              valid;
   datetime          start;
   datetime          end;
   double            poc;
   double            vah;
   double            val;
   double            close;
   double            lo;       // precio inferior del perfil
   double            step;     // alto de cada fila
   int               pocIdx;
   int               loIdx;    // fila del VAL
   int               hiIdx;    // fila del VAH
  };

enum BO_STAGE { BO_WAIT=0, BO_BROKEN=1, BO_PULLBACK=2, BO_DONE=3 };

struct BreakoutState
  {
   BO_STAGE          stage;
   double            extreme;     // máximo (alcista) / mínimo (bajista) desde la ruptura
   double            pullbackExt; // mínimo (alcista) / máximo (bajista) del pullback
   bool              retestOnly;  // la sesión abrió fuera: solo vale el retest al VA
  };

struct ReversalState
  {
   bool              armed;       // el precio está fuera del VA esperando volver
   double            extreme;     // swing más extremo fuera del VA (para el SL)
   int               count;       // reversals tomados en este lado en la sesión
  };

//--- Globales -------------------------------------------------------
CTrade         g_trade;
int            g_atrHandle   = INVALID_HANDLE;
int            g_adxHandle   = INVALID_HANDLE;
int            g_atrD1Handle = INVALID_HANDLE;
datetime       g_lastBarTime = 0;
datetime       g_sessionStart = 0;
Profile        g_prof;
BreakoutState  g_boBull, g_boBear;
ReversalState  g_revAbove, g_revBelow;
bool           g_pocDone  = false;
int            g_trendDir = 0;    // +1 tendencia alcista, -1 bajista, 0 sin tendencia

//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_atrHandle   = iATR(_Symbol, InpEntryTF, InpATRPeriod);
   g_adxHandle   = iADX(_Symbol, InpEntryTF, InpADXPeriod);
   g_atrD1Handle = iATR(_Symbol, PERIOD_D1, 14);
   if(g_atrHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE || g_atrD1Handle == INVALID_HANDLE)
     {
      Print("No se pudieron crear los indicadores");
      return INIT_FAILED;
     }
   if(InpProfileBins < 10 || InpValueAreaPct <= 0 || InpValueAreaPct >= 100)
     {
      Print("Parámetros del perfil inválidos");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_prof.valid = false;
   ResetStates();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle   != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle   != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_atrD1Handle != INVALID_HANDLE) IndicatorRelease(g_atrD1Handle);
   ObjectsDeleteAll(0, "VPEA_");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManagePositions();

   //--- Trabajamos solo al cierre de cada vela de la temporalidad de entrada
   datetime barTime = iTime(_Symbol, InpEntryTF, 0);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   //--- ¿Nueva sesión? -> calcular el Volume Profile de la sesión anterior
   datetime curStart = SessionStartFor(TimeCurrent());
   if(curStart != g_sessionStart || !g_prof.valid)
     {
      if(curStart != g_sessionStart && g_sessionStart != 0 && InpCloseAtSessionEnd)
         CloseAllPositions();
      if(curStart != g_sessionStart)
         ResetStates();
      g_sessionStart = curStart;

      double vol[];
      g_prof.valid = BuildProfileBefore(curStart, g_prof, vol);
      if(g_prof.valid)
        {
         PrintFormat("Perfil %s: POC=%.2f VAH=%.2f VAL=%.2f Cierre=%.2f (%s)",
                     TimeToString(g_prof.start, TIME_DATE), g_prof.poc, g_prof.vah, g_prof.val, g_prof.close,
                     g_prof.close > g_prof.vah ? "fuera arriba" : g_prof.close < g_prof.val ? "fuera abajo" : "dentro");
         if(InpDrawProfile)
            DrawProfiles(curStart);
        }
     }
   if(!g_prof.valid)
      return;

   //--- Velas cerradas: b[0] = última cerrada, b[1] = anterior
   MqlRates b[];
   ArraySetAsSeries(b, true);
   if(CopyRates(_Symbol, InpEntryTF, 1, 2, b) < 2)
      return;
   if(b[0].time < curStart)   // aún no hay velas cerradas de la sesión actual
      return;

   double atr = GetBuffer(g_atrHandle, 0);
   if(atr <= 0)
      return;

   if(InpUseTrendDetect)
      UpdateTrend(b[0], atr);

   //--- Las máquinas de estado se actualizan siempre; la entrada solo si se permite
   bool canTrade = CanOpenTrade();

   if(InpUseReversal)
      ProcessReversal(b[0], atr, canTrade);
   canTrade = canTrade && !HasOpenPosition();

   if(InpUseBreakout)
      ProcessBreakout(b[0], b[1], atr, canTrade);
   canTrade = canTrade && !HasOpenPosition();

   if(InpUsePOCBounce && !g_pocDone && b[1].time >= curStart)
      ProcessPOCBounce(b[0], b[1], atr, canTrade);
  }

//+------------------------------------------------------------------+
//| SESIONES Y VOLUME PROFILE                                        |
//| Replica el Fixed Range Volume Profile de TradingView:            |
//|  - rango = sesión completa anterior (primera a última vela)      |
//|  - el volumen de cada vela M1 se reparte entre su high y su low  |
//|  - POC = fila con más volumen                                    |
//|  - VA  = se expande desde el POC hasta juntar el 70 %            |
//+------------------------------------------------------------------+
datetime SessionStartFor(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = InpSessionStartHour;
   dt.min  = InpSessionStartMinute;
   dt.sec  = 0;
   datetime s = StructToTime(dt);
   if(s > t)
      s -= 86400;
   return s;
  }

//--- Perfil de la última sesión con datos que termina en 'end' (salta fines de semana)
bool BuildProfileBefore(datetime end, Profile &p, double &vol[])
  {
   for(int k = 0; k < 7; k++)
     {
      datetime start = end - 86400;
      MqlRates r[];
      int n = CopyRates(_Symbol, InpProfileTF, start, end - 1, r);
      if(n >= InpMinSessionBars)
         return ComputeProfile(r, n, start, end, p, vol);
      end = start;
     }
   return false;
  }

bool ComputeProfile(const MqlRates &r[], int n, datetime start, datetime end, Profile &p, double &vol[])
  {
   double hi = r[0].high, lo = r[0].low;
   for(int i = 1; i < n; i++)
     {
      hi = MathMax(hi, r[i].high);
      lo = MathMin(lo, r[i].low);
     }
   if(hi <= lo)
      return false;

   int    bins = InpProfileBins;
   double step = (hi - lo) / bins;
   ArrayResize(vol, bins);
   ArrayInitialize(vol, 0.0);

   double total = 0;
   for(int i = 0; i < n; i++)
     {
      double v = InpUseRealVolume ? (double)r[i].real_volume : (double)r[i].tick_volume;
      if(v <= 0)
         continue;
      int b0 = (int)MathFloor((r[i].low  - lo) / step);
      int b1 = (int)MathFloor((r[i].high - lo) / step);
      b0 = MathMax(0, MathMin(bins - 1, b0));
      b1 = MathMax(0, MathMin(bins - 1, b1));
      double share = v / (b1 - b0 + 1);
      for(int b = b0; b <= b1; b++)
         vol[b] += share;
      total += v;
     }
   if(total <= 0)
      return false;

   int pocIdx = ArrayMaximum(vol, 0, bins);

   int    loIdx = pocIdx, hiIdx = pocIdx;
   double acc = vol[pocIdx];
   double target = total * InpValueAreaPct / 100.0;
   while(acc < target && (loIdx > 0 || hiIdx < bins - 1))
     {
      double up = (hiIdx < bins - 1) ? vol[hiIdx + 1] : -1.0;
      double dn = (loIdx > 0)        ? vol[loIdx - 1] : -1.0;
      if(up >= dn) { hiIdx++; acc += up; }
      else         { loIdx--; acc += dn; }
     }

   p.start  = r[0].time;
   p.end    = r[n - 1].time + PeriodSeconds(InpProfileTF);
   p.lo     = lo;
   p.step   = step;
   p.pocIdx = pocIdx;
   p.loIdx  = loIdx;
   p.hiIdx  = hiIdx;
   p.poc    = lo + (pocIdx + 0.5) * step;
   p.vah    = lo + (hiIdx + 1) * step;
   p.val    = lo + loIdx * step;
   p.close  = r[n - 1].close;
   p.valid  = true;
   return true;
  }

//+------------------------------------------------------------------+
//| DETECCIÓN DE DÍA DE TENDENCIA                                    |
//| 3 señales medibles; si se cumplen InpTrendMinScore -> tendencia. |
//| Se mantiene hasta que una vela cierre de vuelta dentro del VA.   |
//+------------------------------------------------------------------+
void UpdateTrend(const MqlRates &c, double atr)
  {
   int side = 0;
   double dist = 0;
   if(c.close > g_prof.vah)      { side = +1; dist = c.close - g_prof.vah; }
   else if(c.close < g_prof.val) { side = -1; dist = g_prof.val - c.close; }

   if(side == 0)
     {
      if(g_trendDir != 0)
         Print("Tendencia terminada: el precio volvió a cerrar dentro del VA");
      g_trendDir = 0;
      return;
     }
   if(g_trendDir == side)
      return;

   int score = 0;
   //--- Señal 1: se alejó mucho del VA
   if(dist >= InpTrendDistATR * atr)
      score++;
   //--- Señal 2: ADX fuerte con la dirección correcta
   double adx = GetBuffer(g_adxHandle, 0);
   double pdi = GetBuffer(g_adxHandle, 1);
   double mdi = GetBuffer(g_adxHandle, 2);
   if(adx >= InpTrendADX && ((side > 0 && pdi > mdi) || (side < 0 && mdi > pdi)))
      score++;
   //--- Señal 3: el VA de ayer fue angosto (compresión -> expansión)
   double atrD1 = GetBuffer(g_atrD1Handle, 0);   // ATR diario de ayer
   if(atrD1 > 0 && (g_prof.vah - g_prof.val) <= InpTrendNarrowVA * atrD1)
      score++;

   if(score >= InpTrendMinScore)
     {
      g_trendDir = side;
      PrintFormat("DÍA DE TENDENCIA %s detectado (señales %d/3, ADX %.1f, distancia %.1f ATR)",
                  side > 0 ? "ALCISTA" : "BAJISTA", score, adx, dist / atr);
     }
  }

//+------------------------------------------------------------------+
//| ESTRATEGIA #1: POC BOUNCE                                        |
//+------------------------------------------------------------------+
void ProcessPOCBounce(const MqlRates &c, const MqlRates &prev, double atr, bool canTrade)
  {
   bool bullBias = g_prof.close > g_prof.vah;  // sesión anterior cerró ARRIBA del VA
   bool bearBias = g_prof.close < g_prof.val;  // sesión anterior cerró ABAJO del VA
   if(!bullBias && !bearBias)
      return;

   double poc    = g_prof.poc;
   double tol    = InpPOCTouchATR * atr;
   double pierce = InpPOCMaxPierceATR * atr;
   double buffer = InpSLBufferATR * atr;

   if(bullBias)
     {
      double minLow = MathMin(c.low, prev.low);
      bool touched  = (minLow <= poc + tol) && (minLow >= poc - pierce);
      bool engulf   = prev.close < prev.open && c.close > c.open &&
                      c.close >= prev.open && c.open <= prev.close;
      bool pin      = InpPOCAllowPinBar && IsBullPin(c);
      if(touched && (engulf || pin) && c.close > poc)
        {
         g_pocDone = true;
         if(canTrade)
            OpenTrade(ORDER_TYPE_BUY, MathMin(minLow, poc) - buffer, InpRR_POC, atr, "POC_Bounce");
        }
     }
   else
     {
      double maxHigh = MathMax(c.high, prev.high);
      bool touched   = (maxHigh >= poc - tol) && (maxHigh <= poc + pierce);
      bool engulf    = prev.close > prev.open && c.close < c.open &&
                       c.close <= prev.open && c.open >= prev.close;
      bool pin       = InpPOCAllowPinBar && IsBearPin(c);
      if(touched && (engulf || pin) && c.close < poc)
        {
         g_pocDone = true;
         if(canTrade)
            OpenTrade(ORDER_TYPE_SELL, MathMax(maxHigh, poc) + buffer, InpRR_POC, atr, "POC_Bounce");
        }
     }
  }

bool IsBullPin(const MqlRates &c)
  {
   double range = c.high - c.low;
   if(range <= 0) return false;
   double body = MathAbs(c.close - c.open);
   double lowerWick = MathMin(c.open, c.close) - c.low;
   return lowerWick >= 2.0 * body && MathMin(c.open, c.close) >= c.low + range * 0.6;
  }

bool IsBearPin(const MqlRates &c)
  {
   double range = c.high - c.low;
   if(range <= 0) return false;
   double body = MathAbs(c.close - c.open);
   double upperWick = c.high - MathMax(c.open, c.close);
   return upperWick >= 2.0 * body && MathMax(c.open, c.close) <= c.high - range * 0.6;
  }

//+------------------------------------------------------------------+
//| ESTRATEGIA #2: VALUE AREA REVERSAL                               |
//+------------------------------------------------------------------+
void ProcessReversal(const MqlRates &c, double atr, bool canTrade)
  {
   if(g_prof.close > g_prof.vah || g_prof.close < g_prof.val)
      return;   // solo válido si la sesión anterior cerró DENTRO del VA

   double vah = g_prof.vah, val = g_prof.val;
   double buffer = InpSLBufferATR * atr;
   bool closedInside = c.close < vah && c.close > val;   // cierre de vela, no mecha
   bool aboveAllowed = InpRevMaxPerSide <= 0 || g_revAbove.count < InpRevMaxPerSide;
   bool belowAllowed = InpRevMaxPerSide <= 0 || g_revBelow.count < InpRevMaxPerSide;

   //--- Excursión por ARRIBA del VAH -> venta al volver a cerrar dentro
   if(!g_revAbove.armed)
     {
      if(c.high > vah)
        {
         if(c.close > vah)
           { g_revAbove.armed = true; g_revAbove.extreme = c.high; }
         else if(!InpRevRequireCloseOutside && closedInside && canTrade && aboveAllowed)
           {
            if(OpenTrade(ORDER_TYPE_SELL, c.high + buffer, InpRR_Reversal, atr, "VA_Reversal"))
              { g_revAbove.count++; canTrade = false; }
           }
        }
     }
   else
     {
      g_revAbove.extreme = MathMax(g_revAbove.extreme, c.high);
      if(closedInside)
        {
         g_revAbove.armed = false;
         if(canTrade && aboveAllowed &&
            OpenTrade(ORDER_TYPE_SELL, g_revAbove.extreme + buffer, InpRR_Reversal, atr, "VA_Reversal"))
           { g_revAbove.count++; canTrade = false; }
        }
      else if(c.close < val)
         g_revAbove.armed = false;
     }

   //--- Excursión por DEBAJO del VAL -> compra al volver a cerrar dentro
   if(!g_revBelow.armed)
     {
      if(c.low < val)
        {
         if(c.close < val)
           { g_revBelow.armed = true; g_revBelow.extreme = c.low; }
         else if(!InpRevRequireCloseOutside && closedInside && canTrade && belowAllowed)
           {
            if(OpenTrade(ORDER_TYPE_BUY, c.low - buffer, InpRR_Reversal, atr, "VA_Reversal"))
               g_revBelow.count++;
           }
        }
     }
   else
     {
      g_revBelow.extreme = MathMin(g_revBelow.extreme, c.low);
      if(closedInside)
        {
         g_revBelow.armed = false;
         if(canTrade && belowAllowed &&
            OpenTrade(ORDER_TYPE_BUY, g_revBelow.extreme - buffer, InpRR_Reversal, atr, "VA_Reversal"))
            g_revBelow.count++;
        }
      else if(c.close > vah)
         g_revBelow.armed = false;
     }
  }

//+------------------------------------------------------------------+
//| ESTRATEGIA #3: BREAKOUT -> PULLBACK -> BOS                       |
//+------------------------------------------------------------------+
void ProcessBreakout(const MqlRates &c, const MqlRates &prev, double atr, bool canTrade)
  {
   double vah = g_prof.vah, val = g_prof.val;
   double maxDepth = (vah - val) * InpBOMaxDepthPct / 100.0;
   double pbZone   = InpBOPullbackATR * atr;
   double buffer   = InpSLBufferATR * atr;

   //================ ALCISTA: ruptura del VAH ================
   switch(g_boBull.stage)
     {
      case BO_WAIT:
         if(c.close > vah)
           {
            bool crossed = prev.close <= vah;   // ruptura real: venía de adentro
            if(!crossed && InpBOOpenOutside == OPEN_IGNORE)
               break;
            g_boBull.stage = BO_BROKEN;
            g_boBull.extreme = c.high;
            g_boBull.retestOnly = !crossed && InpBOOpenOutside == OPEN_RETEST;
           }
         break;
      case BO_BROKEN:
        {
         if(c.close < vah - maxDepth)                  // volvió muy adentro: inválido
           { g_boBull.stage = BO_WAIT; break; }
         bool inZone = c.low <= vah + pbZone;
         double impulse = g_boBull.extreme - vah;
         bool retraced = impulse >= InpBOMinImpulseATR * atr &&
                         (g_boBull.extreme - c.low) >= impulse * InpBORetracePct / 100.0;
         bool pullback = PullbackOK(inZone, retraced, g_boBull.retestOnly);
         if(pullback)
           { g_boBull.stage = BO_PULLBACK; g_boBull.pullbackExt = c.low; }
         else
            g_boBull.extreme = MathMax(g_boBull.extreme, c.high);
         break;
        }
      case BO_PULLBACK:
         g_boBull.pullbackExt = MathMin(g_boBull.pullbackExt, c.low);
         if(c.close < vah - maxDepth)
           { g_boBull.stage = BO_WAIT; break; }
         if(c.close > g_boBull.extreme)                // BOS: máximo más alto
           {
            g_boBull.stage = BO_DONE;
            if(canTrade &&
               OpenTrade(ORDER_TYPE_BUY, g_boBull.pullbackExt - buffer, InpRR_Breakout, atr, "VA_Breakout"))
               canTrade = false;
           }
         break;
      default:
         break;
     }

   //================ BAJISTA: ruptura del VAL ================
   switch(g_boBear.stage)
     {
      case BO_WAIT:
         if(c.close < val)
           {
            bool crossed = prev.close >= val;
            if(!crossed && InpBOOpenOutside == OPEN_IGNORE)
               break;
            g_boBear.stage = BO_BROKEN;
            g_boBear.extreme = c.low;
            g_boBear.retestOnly = !crossed && InpBOOpenOutside == OPEN_RETEST;
           }
         break;
      case BO_BROKEN:
        {
         if(c.close > val + maxDepth)
           { g_boBear.stage = BO_WAIT; break; }
         bool inZone = c.high >= val - pbZone;
         double impulse = val - g_boBear.extreme;
         bool retraced = impulse >= InpBOMinImpulseATR * atr &&
                         (c.high - g_boBear.extreme) >= impulse * InpBORetracePct / 100.0;
         bool pullback = PullbackOK(inZone, retraced, g_boBear.retestOnly);
         if(pullback)
           { g_boBear.stage = BO_PULLBACK; g_boBear.pullbackExt = c.high; }
         else
            g_boBear.extreme = MathMin(g_boBear.extreme, c.low);
         break;
        }
      case BO_PULLBACK:
         g_boBear.pullbackExt = MathMax(g_boBear.pullbackExt, c.high);
         if(c.close > val + maxDepth)
           { g_boBear.stage = BO_WAIT; break; }
         if(c.close < g_boBear.extreme)                // BOS: mínimo más bajo
           {
            g_boBear.stage = BO_DONE;
            if(canTrade)
               OpenTrade(ORDER_TYPE_SELL, g_boBear.pullbackExt + buffer, InpRR_Breakout, atr, "VA_Breakout");
           }
         break;
      default:
         break;
     }
  }

//--- ¿El retroceso cuenta como pullback según la configuración?
bool PullbackOK(bool inZone, bool retraced, bool retestOnly)
  {
   if(retestOnly)                 // abrió fuera del VA: solo vale volver al borde del VA
      return inZone;
   switch(InpBOPullbackMode)
     {
      case PB_VA_ZONE: return inZone;
      case PB_IMPULSE: return retraced;
      default:         return inZone || retraced;
     }
  }

//+------------------------------------------------------------------+
//| FILTROS Y GESTIÓN DE RIESGO                                      |
//+------------------------------------------------------------------+
bool CanOpenTrade()
  {
   if(HasOpenPosition())
      return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpTradeStartHour || dt.hour >= InpTradeEndHour)
      return false;

   if(InpMaxSpreadPoints > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints)
      return false;

   if(NewsBlocked())
      return false;

   //--- Estadísticas de la sesión actual desde el historial (sobrevive a reinicios)
   int    entries = 0, consecLosses = 0;
   double closedPL = 0;
   if(HistorySelect(g_sessionStart, TimeCurrent() + 60))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0) continue;
         if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic) continue;
         long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
            entries++;
         else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
           {
            double pl = HistoryDealGetDouble(tk, DEAL_PROFIT) +
                        HistoryDealGetDouble(tk, DEAL_SWAP) +
                        HistoryDealGetDouble(tk, DEAL_COMMISSION);
            closedPL += pl;
            if(pl < 0) consecLosses++;
            else       consecLosses = 0;
           }
        }
     }

   if(entries >= InpMaxTradesPerSession)
      return false;
   if(InpMaxConsecLosses > 0 && consecLosses >= InpMaxConsecLosses)
      return false;

   double startBalance = AccountInfoDouble(ACCOUNT_BALANCE) - closedPL;
   if(startBalance > 0 && closedPL <= -startBalance * InpMaxDailyLossPct / 100.0)
      return false;

   return true;
  }

//--- Calendario económico de MT5: ¿hay noticia importante cerca?
//    Nota: el calendario NO está disponible en el Probador de Estrategias.
bool NewsBlocked()
  {
   if(!InpUseNewsFilter || MQLInfoInteger(MQL_TESTER))
      return false;

   static datetime lastCheck = 0;
   static bool     blocked   = false;
   datetime now = TimeTradeServer();
   if(now - lastCheck < 60)
      return blocked;
   lastCheck = now;
   blocked = false;

   string currencies[2];
   currencies[0] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);    // XAU
   currencies[1] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);  // USD
   datetime from = now - InpNewsMinutesAfter * 60;
   datetime to   = now + InpNewsMinutesBefore * 60;

   for(int c = 0; c < 2 && !blocked; c++)
     {
      if(c == 1 && currencies[1] == currencies[0]) break;
      MqlCalendarValue values[];
      if(CalendarValueHistory(values, from, to, NULL, currencies[c]) <= 0)
         continue;
      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev))
            continue;
         if(ev.importance == CALENDAR_IMPORTANCE_HIGH ||
            (InpNewsIncludeMedium && ev.importance == CALENDAR_IMPORTANCE_MODERATE))
           {
            PrintFormat("Filtro de noticias: %s a las %s, no se abren operaciones",
                        ev.name, TimeToString(values[i].time, TIME_MINUTES));
            blocked = true;
            break;
           }
        }
     }
   return blocked;
  }

double CalcLots(double slDistance)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double volMin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tickValue <= 0 || tickSize <= 0 || volStep <= 0 || slDistance <= 0)
      return 0;

   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lossPerLot = slDistance / tickSize * tickValue;
   double lots = MathFloor(riskMoney / lossPerLot / volStep) * volStep;

   if(lots < volMin)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double minLotRiskPct = (balance > 0) ? lossPerLot * volMin / balance * 100.0 : 1000.0;
      if(minLotRiskPct > InpMaxRiskPctMinLot)
        {
         PrintFormat("Lote mínimo arriesga %.1f%% (> %.1f%% permitido), se ignora", minLotRiskPct, InpMaxRiskPctMinLot);
         return 0;
        }
      PrintFormat("AVISO: usando lote mínimo %.2f, arriesga %.1f%% de la cuenta", volMin, minLotRiskPct);
      lots = volMin;
     }
   return MathMin(lots, volMax);
  }

//--- Abre la operación. Devuelve true si se abrió.
bool OpenTrade(ENUM_ORDER_TYPE type, double sl, double rr, double atr, string tag)
  {
   bool isBuy = (type == ORDER_TYPE_BUY);
   int  dir   = isBuy ? +1 : -1;

   //--- Día de tendencia: no operar en contra
   if(InpUseTrendDetect && InpTrendBlockCounter && g_trendDir != 0 && dir != g_trendDir)
     {
      PrintFormat("%s: bloqueada, va en contra del día de tendencia", tag);
      return false;
     }

   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double risk  = isBuy ? price - sl : sl - price;
   if(risk <= 0)
     {
      PrintFormat("%s: SL inválido (precio ya pasó el stop)", tag);
      return false;
     }
   if(risk > InpMaxSLATR * atr)
     {
      PrintFormat("%s: SL demasiado grande (%.1f ATR), se ignora", tag, risk / atr);
      return false;
     }
   double minStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(risk < minStop)
     {
      PrintFormat("%s: SL menor al mínimo del broker", tag);
      return false;
     }

   double lots = CalcLots(risk);
   if(lots <= 0)
      return false;

   double margin = 0;
   if(OrderCalcMargin(type, _Symbol, lots, price, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      PrintFormat("%s: margen insuficiente (necesita %.2f)", tag, margin);
      return false;
     }

   //--- Take Profit según el modo
   double tp = isBuy ? price + rr * risk : price - rr * risk;
   bool trailOn  = InpTrailMode != TRAIL_OFF;
   bool partial  = InpUsePartial && CanSplit(lots);
   bool runner   = InpUseTrendDetect && InpTrendRunner && trailOn && g_trendDir == dir;

   if(partial)
     {
      //--- El TP de la parte que se cierra lo maneja el EA a InpPartialAtR;
      //    la orden lleva el TP del "runner" (resto).
      double runnerR = InpRunnerTP_R;
      if(runnerR <= 0 && !trailOn)
         runnerR = 2.0 * InpPartialAtR;   // sin trailing, el resto necesita un TP
      tp = (runnerR > 0) ? (isBuy ? price + runnerR * risk : price - runnerR * risk) : 0;
     }
   if((InpTrailNoTP && trailOn) || runner)
      tp = 0;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   string comment = tag + (runner ? "_T" : "");
   bool ok = isBuy ? g_trade.Buy(lots, _Symbol, 0, sl, tp, comment)
                   : g_trade.Sell(lots, _Symbol, 0, sl, tp, comment);
   PrintFormat("%s %s lots=%.2f SL=%.2f TP=%.2f%s%s -> %s (%u)",
               tag, isBuy ? "BUY" : "SELL", lots, sl, tp,
               partial ? " [parcial]" : "", runner ? " [tendencia: sin TP]" : "",
               ok ? "OK" : "ERROR", g_trade.ResultRetcode());

   if(ok && g_trade.ResultOrder() > 0)
     {
      ulong id = g_trade.ResultOrder();
      GlobalVariableSet(GVKey("R", id), risk);         // 1R para breakeven/trailing
      if(partial)
         GlobalVariableSet(GVKey("P", id), 1.0);       // parcial pendiente
     }
   return ok;
  }

//--- ¿Se puede partir la posición en dos partes >= lote mínimo?
bool CanSplit(double lots)
  {
   double volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(volStep <= 0) return false;
   double part = MathFloor(lots * InpPartialPct / 100.0 / volStep) * volStep;
   return part >= volMin && (lots - part) >= volMin - 1e-9;
  }

string GVKey(string kind, ulong positionId)
  {
   return StringFormat("VPEA_%s_%I64d_%I64u", kind, InpMagic, positionId);
  }

//--- Cierre parcial + breakeven + trailing. El stop solo se mueve a favor.
void ManagePositions()
  {
   double atr = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      bool   isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      ulong  posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(sl == 0) continue;

      //--- Riesgo inicial (1R)
      double R = 0;
      string rKey = GVKey("R", posId);
      if(GlobalVariableCheck(rKey))
         R = GlobalVariableGet(rKey);
      else if((isBuy && sl < open) || (!isBuy && sl > open))
        {
         R = MathAbs(open - sl);
         GlobalVariableSet(rKey, R);
        }
      if(R <= 0) continue;

      double price  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profit = isBuy ? price - open : open - price;
      double newSL  = sl;

      //--- Cierre parcial
      string pKey = GVKey("P", posId);
      if(GlobalVariableCheck(pKey) && profit >= InpPartialAtR * R)
        {
         double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double part = MathFloor(vol * InpPartialPct / 100.0 / volStep) * volStep;
         if(CanSplit(vol) && g_trade.PositionClosePartial(tk, part))
            PrintFormat("Cierre parcial %.2f lotes a %.1fR; el resto corre con stop en breakeven", part, profit / R);
         GlobalVariableDel(pKey);
         newSL = Better(isBuy, newSL, open);   // el resto ya no puede perder
        }

      //--- Breakeven
      if(InpUseBreakeven && profit >= InpBreakevenAtR * R)
         newSL = Better(isBuy, newSL, open);

      //--- Trailing
      if(InpTrailMode != TRAIL_OFF && profit >= InpTrailStartR * R)
        {
         double cand = 0;
         if(atr <= 0) atr = GetBuffer(g_atrHandle, 0);
         if(InpTrailMode == TRAIL_ATR && atr > 0)
            cand = isBuy ? price - InpTrailATRMult * atr : price + InpTrailATRMult * atr;
         else if(InpTrailMode == TRAIL_SWING)
           {
            double buffer = InpSLBufferATR * atr;
            int n = MathMax(1, InpTrailSwingBars);
            if(isBuy)
              {
               int idx = iLowest(_Symbol, InpEntryTF, MODE_LOW, n, 1);
               if(idx >= 0) cand = iLow(_Symbol, InpEntryTF, idx) - buffer;
              }
            else
              {
               int idx = iHighest(_Symbol, InpEntryTF, MODE_HIGH, n, 1);
               if(idx >= 0) cand = iHigh(_Symbol, InpEntryTF, idx) + buffer;
              }
           }
         else if(InpTrailMode == TRAIL_STEP && InpTrailStepR > 0)
           {
            int k = (int)MathFloor(profit / (InpTrailStepR * R)) - 1;
            if(k >= 0)
               cand = isBuy ? open + k * InpTrailStepR * R : open - k * InpTrailStepR * R;
           }
         if(cand > 0)
            newSL = Better(isBuy, newSL, cand);
        }

      //--- Respetar distancia mínima del broker y modificar solo si mejora
      double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(isBuy  && newSL > price - minDist) newSL = price - minDist;
      if(!isBuy && newSL < price + minDist) newSL = price + minDist;
      newSL = NormalizeDouble(newSL, _Digits);

      bool improves = isBuy ? newSL > sl + _Point : newSL < sl - _Point;
      if(improves && PositionSelectByTicket(tk))
         g_trade.PositionModify(tk, newSL, PositionGetDouble(POSITION_TP));
     }
  }

double Better(bool isBuy, double a, double b)
  {
   return isBuy ? MathMax(a, b) : MathMin(a, b);
  }

//+------------------------------------------------------------------+
//| UTILIDADES                                                       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
     }
   return false;
  }

void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         g_trade.PositionClose(tk);
     }
  }

//--- Valor de un indicador en la última vela cerrada (shift 1)
double GetBuffer(int handle, int bufferIndex)
  {
   double buf[];
   if(CopyBuffer(handle, bufferIndex, 1, 1, buf) < 1)
      return 0;
   return buf[0];
  }

void ResetStates()
  {
   g_boBull.stage = BO_WAIT; g_boBull.extreme = 0; g_boBull.pullbackExt = 0; g_boBull.retestOnly = false;
   g_boBear.stage = BO_WAIT; g_boBear.extreme = 0; g_boBear.pullbackExt = 0; g_boBear.retestOnly = false;
   g_revAbove.armed = false; g_revAbove.extreme = 0; g_revAbove.count = 0;
   g_revBelow.armed = false; g_revBelow.extreme = 0; g_revBelow.count = 0;
   g_pocDone  = false;
   g_trendDir = 0;
  }

//+------------------------------------------------------------------+
//| DIBUJO: histograma del Volume Profile + POC/VAH/VAL extendidos   |
//| a la sesión siguiente (igual que el paso 4 de la guía).          |
//+------------------------------------------------------------------+
void DrawProfiles(datetime curStart)
  {
   ObjectsDeleteAll(0, "VPEA_");
   datetime end = curStart;
   for(int k = 0; k < MathMax(1, InpDrawSessions); k++)
     {
      Profile p;
      double vol[];
      if(!BuildProfileBefore(end, p, vol))
         break;
      // niveles extendidos hasta el final de la sesión donde se usan
      DrawOneProfile(k, p, vol, end + 86400);
      end = SessionStartFor(p.start);
     }
   ChartRedraw();
  }

void DrawOneProfile(int k, const Profile &p, const double &vol[], datetime levelsEnd)
  {
   string pre = StringFormat("VPEA_%d_", k);
   double maxVol = vol[p.pocIdx];
   if(maxVol <= 0) return;
   double width = (double)(p.end - p.start) * InpHistWidthPct / 100.0;

   for(int b = 0; b < ArraySize(vol); b++)
     {
      if(vol[b] <= 0) continue;
      datetime t2 = p.start + (long)(width * vol[b] / maxVol);
      double   y1 = p.lo + b * p.step;
      double   y2 = y1 + p.step;
      color    clr = (b == p.pocIdx) ? InpColorPOC : (b >= p.loIdx && b <= p.hiIdx) ? InpColorVA : InpColorOut;
      string   nm = pre + "H" + IntegerToString(b);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, p.start, y1, t2, y2);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_FILL, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
     }
   DrawLine(pre + "POC", p.start, levelsEnd, p.poc, InpColorPOC, STYLE_SOLID, 2);
   DrawLine(pre + "VAH", p.start, levelsEnd, p.vah, InpColorVAEdges, STYLE_SOLID, 1);
   DrawLine(pre + "VAL", p.start, levelsEnd, p.val, InpColorVAEdges, STYLE_SOLID, 1);
  }

void DrawLine(string name, datetime t1, datetime t2, double price, color clr, ENUM_LINE_STYLE style, int width)
  {
   ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, StringFormat("%s %.2f", name, price));
  }
//+------------------------------------------------------------------+
