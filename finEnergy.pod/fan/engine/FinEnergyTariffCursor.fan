** One device's canonical hourly billing prefix. Consume each original full
** hour only after that hour's consumers; never retain source readers or ticks.
internal class FinEnergyTariffCursor
{
  new make(FinEnergyContext ctx,Str id,DateTime cycle,FinEnergyPreparedOwner owner)
  {
    record:=ctx.byId[id] ?: throw ArgErr("tariffCursorMeter")
    if(!["meter","totalMeter"].contains(record["kind"])) throw ArgErr("tariffCursorMeter")
    mode:=ctx.tariff(record)?.get("mode") as Str ?: ""
    if(!["monthlyBlock","yearlyBlock"].contains(mode)) throw ArgErr("tariffCursorMode")
    period=mode == "yearlyBlock" ? "year" : "month"
    if(cycle != FinEnergyMath.bucket(cycle,period)) throw ArgErr("tariffCursorCycle")
    this.ctx=ctx;this.record=record;watermark=cycle
    fold.add(FinEnergyValue(0f,"ok"))
    owner.watch |->Void| {close};owner.hold(16)
    ctx.bindTariffCursor(id,this,owner)
  }
  private FinEnergyContext? ctx
  private [Str:Obj?]? record
  private FinEnergyValueFold? fold := FinEnergyValueFold.strict
  private Str period
  private DateTime watermark

  ** A disjoint planned window can start a new billing cycle. A gap inside a
  ** cycle cannot establish its prefix and must never be silently skipped.
  internal Void align(DateTime at)
  {
    if(ctx == null) throw ArgErr("tariffCursorClosed")
    if(at == watermark) return
    if(at < watermark || at != FinEnergyMath.bucket(at,period)) throw ArgErr("tariffCursorWindow")
    fold=FinEnergyValueFold.strict;fold.add(FinEnergyValue(0f,"ok"));watermark=at
  }

  FinEnergyValue baseline(DateTime from,DateTime to,Str[] path)
  {
    if(ctx == null) throw ArgErr("tariffCursorClosed")
    if(from < watermark || from >= watermark+1hr || to <= from || to > watermark+1hr) throw ArgErr("tariffCursorWindow")
    prefix:=fold.finish
    if(from > watermark) prefix=FinEnergyValue.sum([prefix,ctx.ownRaw(record,watermark,from,path)])
    return prefix
  }
  Void consumeHour()
  {
    if(ctx == null) throw ArgErr("tariffCursorClosed")
    end:=watermark+1hr
    value:=ctx.ownRaw(record,watermark,end,Str[,])
    if(value.quality == "streamingReadNotPrepared") throw ArgErr("tariffCursorWindow")
    fold.add(value)
    if(FinEnergyMath.bucket(end,period) != FinEnergyMath.bucket(watermark,period))
    {fold=FinEnergyValueFold.strict;fold.add(FinEnergyValue(0f,"ok"))}
    watermark=end
  }
  private Void close() {ctx=null;record=null;fold=null}
}
