//+------------------------------------------------------------------+
//|                                             VolumeProfileEA.mq5  |
//|  Estrategias basadas en el Volume Profile de la sesión anterior: |
//|   #1 POC Bounce : la sesión anterior cerró fuera del Value Area, |
//|                   el precio vuelve al POC y lo rechaza con una   |
//|                   vela envolvente (engulfing).                   |
//|   #2 VA Reversal: la sesión anterior cerró DENTRO del VA, el     |
//|                   precio sale del VA y una vela CIERRA de vuelta |
//|                   adentro -> entrada a favor de la reversión.    |
//|   #3 Breakout   : el precio rompe VAH/VAL, hace pullback al VA   |
//|                   sin meterse demasiado y luego rompe estructura |
//|                   (BOS) a favor de la ruptura.                   |
//+------------------------------------------------------------------+
#property copyright "frankhdz48"
#property version   "1.10"
#property description "POC Bounce + VA Reversal + VA Breakout (Volume Profile de la sesión anterior)"

#include <Trade/Trade.mqh>

//--- Entradas -------------------------------------------------------
input group "=== Estrategias ==="
input bool   InpUsePOCBounce        = true;   // Activar Estrategia #1 POC Bounce
input bool   InpUseReversal         = true;   // Activar Estrategia #2 Value Area Reversal
input bool   InpUseBreakout         = true;   // Activar Estrategia #3 Breakout

input group "=== Sesión / Volume Profile ==="
input int    InpSessionStartHour    = 0;      // Hora de inicio de sesión (hora del SERVIDOR)
input int    InpSessionStartMinute  = 0;      // Minuto de inicio de sesión
input ENUM_TIMEFRAMES InpProfileTF  = PERIOD_M1; // Temporalidad para construir el perfil
input int    InpProfileBins         = 60;     // Número de filas del perfil (Row Size de la guía = 60)
input double InpValueAreaPct        = 70.0;   // % de volumen del Value Area
input bool   InpUseRealVolume       = false;  // Usar volumen real (futuros) en vez de tick volume
input int    InpMinSessionBars      = 60;     // Mínimo de velas para considerar una sesión válida

input group "=== Entradas ==="
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_M15; // Temporalidad de entrada
input int    InpATRPeriod           = 14;     // Periodo ATR (para tolerancias)
input double InpPOCTouchATR         = 0.25;   // POC: tolerancia de "toque" (x ATR)
input double InpPOCMaxPierceATR     = 0.50;   // POC: máximo que puede perforar el POC (x ATR)
input bool   InpPOCAllowPinBar      = true;   // POC: aceptar también pin bar como rechazo
input bool   InpRevRequireCloseOutside = true; // Reversal: exigir una vela CERRADA fuera del VA antes de volver
input double InpBOPullbackATR       = 0.50;   // Breakout: distancia al VA que cuenta como pullback (x ATR)
input double InpBOMaxDepthPct       = 30.0;   // Breakout: % máximo del VA que puede volver a entrar
input double InpSLBufferATR         = 0.20;   // Colchón del Stop Loss (x ATR)
input double InpMaxSLATR            = 3.0;    // Ignorar señales con SL mayor a X ATR
input int    InpTradeStartHour      = 0;      // Operar desde (hora servidor)
input int    InpTradeEndHour        = 24;     // Operar hasta (hora servidor)

input group "=== Gestión de riesgo ==="
input double InpRiskPercent         = 1.0;    // Riesgo por operación (% del balance)
input double InpRR_POC              = 2.0;    // Ratio R:R POC Bounce (la guía usa 2R)
input double InpRR_Reversal         = 2.0;    // Ratio R:R VA Reversal (la guía usa 2R)
input double InpRR_Breakout         = 3.0;    // Ratio R:R Breakout
input int    InpMaxTradesPerSession = 3;      // Máx. operaciones por sesión
input double InpMaxDailyLossPct     = 3.0;    // Pérdida máxima diaria (%) -> se detiene
input int    InpMaxConsecLosses     = 2;      // Pérdidas seguidas -> se detiene la sesión (0 = off)
input bool   InpUseBreakeven        = true;   // Mover SL a breakeven
input double InpBreakevenAtR        = 1.0;    // ...cuando el precio avanza X R
input bool   InpCloseAtSessionEnd   = false;  // Cerrar posiciones al terminar la sesión
input int    InpMaxSpreadPoints     = 0;      // Spread máximo en puntos (0 = sin filtro)
input long   InpMagic               = 48001;  // Número mágico
input bool   InpDrawLevels          = true;   // Dibujar POC / VAH / VAL en el gráfico

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
  };

// Etapas de la máquina de estados del Breakout
enum BO_STAGE { BO_WAIT=0, BO_BROKEN=1, BO_PULLBACK=2, BO_DONE=3 };

struct BreakoutState
  {
   BO_STAGE          stage;
   double            extreme;     // máximo (alcista) / mínimo (bajista) desde la ruptura
   double            pullbackExt; // mínimo (alcista) / máximo (bajista) del pullback
  };

// Estado de la Estrategia #2 (una por lado del VA)
struct ReversalState
  {
   bool              armed;       // el precio está fuera del VA esperando volver
   double            extreme;     // swing más extremo fuera del VA (para el SL)
  };

//--- Globales -------------------------------------------------------
CTrade         g_trade;
int            g_atrHandle = INVALID_HANDLE;
datetime       g_lastBarTime = 0;
datetime       g_sessionStart = 0;
Profile        g_prof;
BreakoutState  g_boBull, g_boBear;
ReversalState  g_revAbove, g_revBelow;
bool           g_pocDone = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_atrHandle = iATR(_Symbol, InpEntryTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("No se pudo crear el ATR");
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
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   ObjectsDeleteAll(0, "VPEA_");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(InpUseBreakeven)
      ManageBreakeven();

   //--- Trabajamos solo al cierre de cada vela de la temporalidad de entrada
   datetime barTime = iTime(_Symbol, InpEntryTF, 0);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   //--- ¿Nueva sesión?
   datetime curStart = SessionStartFor(TimeCurrent());
   if(curStart != g_sessionStart || !g_prof.valid)
     {
      if(curStart != g_sessionStart && g_sessionStart != 0 && InpCloseAtSessionEnd)
         CloseAllPositions();
      if(curStart != g_sessionStart)
         ResetStates();
      g_sessionStart = curStart;
      g_prof.valid = BuildPrevProfile(curStart, g_prof);
      if(g_prof.valid)
        {
         PrintFormat("Perfil sesión anterior: POC=%.5f VAH=%.5f VAL=%.5f Cierre=%.5f",
                     g_prof.poc, g_prof.vah, g_prof.val, g_prof.close);
         if(InpDrawLevels)
            DrawLevels();
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

   double atr = GetATR();
   if(atr <= 0)
      return;

   //--- Las máquinas de estado se actualizan siempre; la entrada solo si se permite
   bool canTrade = CanOpenTrade();

   //--- Sistema completo: cada estrategia tiene su propio contexto
   //    POC Bounce -> sesión anterior cerró FUERA del VA
   //    Reversal   -> sesión anterior cerró DENTRO del VA
   //    Breakout   -> cualquier caso
   if(InpUseReversal)
      ProcessReversal(b[0], atr, canTrade);
   canTrade = canTrade && !HasOpenPosition();

   if(InpUseBreakout)
      ProcessBreakout(b[0], atr, canTrade);
   canTrade = canTrade && !HasOpenPosition();

   if(InpUsePOCBounce && !g_pocDone && b[1].time >= curStart)
      ProcessPOCBounce(b[0], b[1], atr, canTrade);
  }

//+------------------------------------------------------------------+
//| Sesiones y Volume Profile                                        |
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

//--- Construye el perfil de la última sesión completa con datos (salta fines de semana)
bool BuildPrevProfile(datetime curStart, Profile &p)
  {
   datetime end = curStart;
   for(int k = 0; k < 7; k++)
     {
      datetime start = end - 86400;
      MqlRates r[];
      int n = CopyRates(_Symbol, InpProfileTF, start, end - 1, r);
      if(n >= InpMinSessionBars)
         return ComputeProfile(r, n, start, end, p);
      end = start;
     }
   Print("No hay datos suficientes para la sesión anterior");
   return false;
  }

bool ComputeProfile(const MqlRates &r[], int n, datetime start, datetime end, Profile &p)
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
   double vol[];
   ArrayResize(vol, bins);
   ArrayInitialize(vol, 0.0);

   //--- Reparte el volumen de cada vela uniformemente entre su low y su high
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

   //--- POC = fila con más volumen
   int pocIdx = ArrayMaximum(vol, 0, bins);

   //--- Value Area: se expande desde el POC hacia el lado con más volumen
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

   p.start = start;
   p.end   = end;
   p.poc   = lo + (pocIdx + 0.5) * step;
   p.vah   = lo + (hiIdx + 1) * step;
   p.val   = lo + loIdx * step;
   p.close = r[n - 1].close;
   p.valid = true;
   return true;
  }

//+------------------------------------------------------------------+
//| Estrategia #1: POC Bounce                                        |
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
   else // bearBias
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
//| Estrategia #2: Value Area Reversal                               |
//| Puede repetirse en la sesión cada vez que el precio sale y       |
//| vuelve a cerrar dentro del VA (limitado por InpMaxTradesPerSession)|
//+------------------------------------------------------------------+
void ProcessReversal(const MqlRates &c, double atr, bool canTrade)
  {
   if(g_prof.close > g_prof.vah || g_prof.close < g_prof.val)
      return;   // solo válido si la sesión anterior cerró DENTRO del VA

   double vah = g_prof.vah, val = g_prof.val;
   double buffer = InpSLBufferATR * atr;
   bool closedInside = c.close < vah && c.close > val;   // cierre de vela, no mecha

   //--- Excursión por ARRIBA del VAH -> venta al volver a cerrar dentro
   if(!g_revAbove.armed)
     {
      if(c.high > vah)
        {
         if(c.close > vah)
           { g_revAbove.armed = true; g_revAbove.extreme = c.high; }
         else if(!InpRevRequireCloseOutside && closedInside && canTrade)
           {
            OpenTrade(ORDER_TYPE_SELL, c.high + buffer, InpRR_Reversal, atr, "VA_Reversal");
            canTrade = false;
           }
        }
     }
   else
     {
      g_revAbove.extreme = MathMax(g_revAbove.extreme, c.high);
      if(closedInside)
        {
         g_revAbove.armed = false;
         if(canTrade)
           {
            OpenTrade(ORDER_TYPE_SELL, g_revAbove.extreme + buffer, InpRR_Reversal, atr, "VA_Reversal");
            canTrade = false;
           }
        }
      else if(c.close < val)          // atravesó todo el VA: ya no es esta reversión
         g_revAbove.armed = false;
     }

   //--- Excursión por DEBAJO del VAL -> compra al volver a cerrar dentro
   if(!g_revBelow.armed)
     {
      if(c.low < val)
        {
         if(c.close < val)
           { g_revBelow.armed = true; g_revBelow.extreme = c.low; }
         else if(!InpRevRequireCloseOutside && closedInside && canTrade)
            OpenTrade(ORDER_TYPE_BUY, c.low - buffer, InpRR_Reversal, atr, "VA_Reversal");
        }
     }
   else
     {
      g_revBelow.extreme = MathMin(g_revBelow.extreme, c.low);
      if(closedInside)
        {
         g_revBelow.armed = false;
         if(canTrade)
            OpenTrade(ORDER_TYPE_BUY, g_revBelow.extreme - buffer, InpRR_Reversal, atr, "VA_Reversal");
        }
      else if(c.close > vah)
         g_revBelow.armed = false;
     }
  }

//+------------------------------------------------------------------+
//| Estrategia #3: Breakout -> Pullback -> BOS                       |
//+------------------------------------------------------------------+
void ProcessBreakout(const MqlRates &c, double atr, bool canTrade)
  {
   double vaWidth  = g_prof.vah - g_prof.val;
   double maxDepth = vaWidth * InpBOMaxDepthPct / 100.0;
   double pbZone   = InpBOPullbackATR * atr;
   double buffer   = InpSLBufferATR * atr;

   //--- Alcista: ruptura del VAH
   switch(g_boBull.stage)
     {
      case BO_WAIT:
         if(c.close > g_prof.vah)
           { g_boBull.stage = BO_BROKEN; g_boBull.extreme = c.high; }
         break;
      case BO_BROKEN:
         if(c.close < g_prof.vah - maxDepth)          // volvió muy adentro: inválido
           { g_boBull.stage = BO_WAIT; break; }
         if(c.low <= g_prof.vah + pbZone)              // pullback al VA
           { g_boBull.stage = BO_PULLBACK; g_boBull.pullbackExt = c.low; }
         else
            g_boBull.extreme = MathMax(g_boBull.extreme, c.high);
         break;
      case BO_PULLBACK:
         g_boBull.pullbackExt = MathMin(g_boBull.pullbackExt, c.low);
         if(c.close < g_prof.vah - maxDepth)
           { g_boBull.stage = BO_WAIT; break; }
         if(c.close > g_boBull.extreme)                // BOS: nuevo máximo más alto
           {
            g_boBull.stage = BO_DONE;
            if(canTrade)
               OpenTrade(ORDER_TYPE_BUY, g_boBull.pullbackExt - buffer, InpRR_Breakout, atr, "VA_Breakout");
           }
         break;
      default:
         break;
     }

   //--- Bajista: ruptura del VAL
   switch(g_boBear.stage)
     {
      case BO_WAIT:
         if(c.close < g_prof.val)
           { g_boBear.stage = BO_BROKEN; g_boBear.extreme = c.low; }
         break;
      case BO_BROKEN:
         if(c.close > g_prof.val + maxDepth)
           { g_boBear.stage = BO_WAIT; break; }
         if(c.high >= g_prof.val - pbZone)
           { g_boBear.stage = BO_PULLBACK; g_boBear.pullbackExt = c.high; }
         else
            g_boBear.extreme = MathMin(g_boBear.extreme, c.low);
         break;
      case BO_PULLBACK:
         g_boBear.pullbackExt = MathMax(g_boBear.pullbackExt, c.high);
         if(c.close > g_prof.val + maxDepth)
           { g_boBear.stage = BO_WAIT; break; }
         if(c.close < g_boBear.extreme)                // BOS: nuevo mínimo más bajo
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

//+------------------------------------------------------------------+
//| Gestión de riesgo                                                |
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

   if(lots < volMin)   // no arriesgar más de lo permitido: mejor no operar
      return 0;
   return MathMin(lots, volMax);
  }

void OpenTrade(ENUM_ORDER_TYPE type, double sl, double rr, double atr, string tag)
  {
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double risk = (type == ORDER_TYPE_BUY) ? price - sl : sl - price;
   if(risk <= 0)
     {
      PrintFormat("%s: SL inválido (precio ya pasó el stop)", tag);
      return;
     }
   if(risk > InpMaxSLATR * atr)
     {
      PrintFormat("%s: SL demasiado grande (%.1f ATR), se ignora", tag, risk / atr);
      return;
     }
   double minStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(risk < minStop)
     {
      PrintFormat("%s: SL menor al mínimo del broker", tag);
      return;
     }

   double tp = (type == ORDER_TYPE_BUY) ? price + rr * risk : price - rr * risk;
   double lots = CalcLots(risk);
   if(lots <= 0)
     {
      PrintFormat("%s: lote calculado menor al mínimo, se ignora", tag);
      return;
     }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   bool ok = (type == ORDER_TYPE_BUY) ? g_trade.Buy(lots, _Symbol, 0, sl, tp, tag)
                                      : g_trade.Sell(lots, _Symbol, 0, sl, tp, tag);
   PrintFormat("%s %s lots=%.2f SL=%.5f TP=%.5f -> %s (%u)",
               tag, (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), lots, sl, tp,
               ok ? "OK" : "ERROR", g_trade.ResultRetcode());
  }

void ManageBreakeven()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      long   type = PositionGetInteger(POSITION_TYPE);
      if(sl == 0) continue;

      if(type == POSITION_TYPE_BUY && sl < open)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - open >= InpBreakevenAtR * (open - sl))
            g_trade.PositionModify(tk, NormalizeDouble(open, _Digits), tp);
        }
      else if(type == POSITION_TYPE_SELL && sl > open)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(open - ask >= InpBreakevenAtR * (sl - open))
            g_trade.PositionModify(tk, NormalizeDouble(open, _Digits), tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Utilidades                                                       |
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

double GetATR()
  {
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) < 1)
      return 0;
   return buf[0];
  }

void ResetStates()
  {
   g_boBull.stage = BO_WAIT; g_boBull.extreme = 0; g_boBull.pullbackExt = 0;
   g_boBear.stage = BO_WAIT; g_boBear.extreme = 0; g_boBear.pullbackExt = 0;
   g_revAbove.armed = false; g_revAbove.extreme = 0;
   g_revBelow.armed = false; g_revBelow.extreme = 0;
   g_pocDone = false;
  }

void DrawLevel(string name, double price, color clr, ENUM_LINE_STYLE style)
  {
   datetime t1 = g_prof.start;
   datetime t2 = g_sessionStart + 86400;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
     {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, name);
  }

void DrawLevels()
  {
   DrawLevel("VPEA_POC", g_prof.poc, clrMagenta, STYLE_SOLID);
   DrawLevel("VPEA_VAH", g_prof.vah, clrSilver, STYLE_DASH);
   DrawLevel("VPEA_VAL", g_prof.val, clrSilver, STYLE_DASH);
   ChartRedraw();
  }
//+------------------------------------------------------------------+
