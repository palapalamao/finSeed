import type {ReportResult} from './types';

type Row=Record<string,unknown>;
// Applied once to the cloned report. Strict results remain explicit, while all
// display/export consumers receive the same available quantity and its quality.
function display(row:Row):Row{
 const output={...row};
 for(const [value,known]of [['value','knownValue'],['valueType','knownValueType'],['quality','knownQuality'],['percentage','knownPercentage'],['current','knownCurrent'],['reference','knownReference'],['working','knownWorking'],['nonworking','knownNonworking'],['workingQuality','knownWorkingQuality'],['nonworkingQuality','knownNonworkingQuality']]){
  if(Object.hasOwn(row,known)){const strict='complete'+value[0].toUpperCase()+value.slice(1);output[strict]=row[value];output[value]=row[known];}
 }
 return output;
}
function rows(value:unknown){return Array.isArray(value)?value.map(row=>row&&typeof row==='object'?display(row as Row):row):value;}
export function applyKnownUsageDisplay(result:ReportResult):void{
 result.series.forEach(series=>{series.points=series.points.map(point=>display(point as unknown as Row) as unknown as typeof point);});
 result.rows=rows(result.rows) as Row[];
 const known=new Map((Array.isArray(result.summary.knownTotals)?result.summary.knownTotals as Row[]:[]).map(row=>[String(row.id),row]));
 if(Array.isArray(result.summary.totals))result.summary.totals=result.summary.totals.map((row:Row)=>{const subtotal=known.get(String(row.id));return display(subtotal?{...row,knownValue:subtotal.value,knownValueType:subtotal.valueType,knownQuality:subtotal.quality}:row);});
 result.summary.selectionTotals=rows(result.summary.selectionTotals);
 if(result.extra){for(const key of ['details','scopeTotals','grandTotals','overview','loadBands','comparisons','utilityShares','utilityMembers','selectionTotals'])if(Array.isArray(result.extra[key]))result.extra[key]=rows(result.extra[key]);
  if(result.kind==='leak'&&Array.isArray(result.extra.leakTotals))result.extra.leakTotals=(result.extra.leakTotals as Row[]).map(row=>{
   if(!Object.hasOwn(row,'knownTotal'))return row;
   const main=typeof row.knownTotal==='number'&&Number.isFinite(row.knownTotal)?row.knownTotal:null;
   const branches=typeof row.knownSubmeter==='number'&&Number.isFinite(row.knownSubmeter)?row.knownSubmeter:null;
   const difference=main!==null&&branches!==null?main-branches:null;
   return {...row,availableDifference:difference,availableDifferencePercentage:difference!==null&&main!==null&&main!==0?difference/main*100:null};
  });
  const graph=result.extra.energyFlow as {nodes?:Row[];unassigned?:Row[]}|undefined;
  const graphs=(Array.isArray(result.extra.energyFlowGraphs)?result.extra.energyFlowGraphs:[]) as {nodes?:Row[];unassigned?:Row[]}[];
  for(const item of new Set([graph,...graphs]))if(item){item.nodes=rows(item.nodes) as Row[];item.unassigned=rows(item.unassigned) as Row[];}
  const segments=result.extra.energyFlowSegments as {energyFlow?:{nodes?:Row[];unassigned?:Row[]};rows?:Row[];series?:ReportResult['series']}[]|undefined;
  for(const segment of segments||[]){if(segment.energyFlow){segment.energyFlow.nodes=rows(segment.energyFlow.nodes) as Row[];segment.energyFlow.unassigned=rows(segment.energyFlow.unassigned) as Row[];}segment.rows=rows(segment.rows) as Row[];segment.series?.forEach(series=>{series.points=series.points.map(point=>display(point as unknown as Row) as unknown as typeof point);});}
 }
}
