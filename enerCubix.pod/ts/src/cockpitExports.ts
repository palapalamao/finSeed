import type {CockpitSnapshot} from './cockpitTypes';
import type {Locale} from './i18n';
import {translateFor} from './i18n';
import {diagnosticSummary,diagnosticHeaders,diagnosticRows} from './cockpitDiagnostics';
export interface CockpitExport {schemaVersion:1;language:Locale;snapshot:CockpitSnapshot;objects:Record<string,string>;diagnosticNotice?:string}
function freeze<T>(value:T):T{if(value&&typeof value==='object'&&!Object.isFrozen(value)){Object.values(value).forEach(freeze);Object.freeze(value);}return value;}
export function freezeCockpitExport(snapshot:CockpitSnapshot,language:Locale,objects:Record<string,string>):CockpitExport{return freeze(structuredClone({schemaVersion:1,language,snapshot,objects,...(snapshot.diagnostics?{diagnosticNotice:diagnosticSummary(snapshot.diagnostics,(key,...values)=>translateFor(language,key,...values))}:{})}));}
const cell=(value:unknown):string|number|boolean=>value==null?'—':typeof value==='number'||typeof value==='boolean'?value:typeof value==='string'?value:JSON.stringify(value);
export function cockpitExportTables(packet:CockpitExport){return Object.entries(packet.snapshot.reports).map(([id,report])=>{
 const keys=[...new Set(report.rows.flatMap(row=>Object.keys(row)))];
 return {id,kind:report.kind,from:report.from,to:report.to,period:report.period,headers:keys,rows:report.rows.map(row=>keys.map(key=>cell(row[key]))),series:report.series.flatMap(series=>series.points.map(point=>[series.id,series.name,series.categoryId||'',series.unit,point.ts,...[point.valueType==='na'?'NA':point.value,point.valueType,point.quality,point.knownValueType==='na'?'NA':point.knownValue,point.knownValueType,point.knownQuality,point.completeValueType==='na'?'NA':point.completeValue,point.completeValueType,point.completeQuality,point.sourceIds].map(cell)]))};});}
function chunks(text:string){const result:string[]=[];for(let start=0;start<text.length;){let end=Math.min(start+30000,text.length);if(end<text.length&&text.charCodeAt(end-1)>=0xd800&&text.charCodeAt(end-1)<=0xdbff)end--;result.push(text.slice(start,end));start=end;}return result;}
export async function cockpitWorkbook(packet:CockpitExport){
 const {Workbook}=await import('exceljs'),book=new Workbook(),tr=(key:string)=>translateFor(packet.language,key),snapshot=packet.snapshot,c=snapshot.context;
 book.creator=tr('能源魔方');book.created=new Date(snapshot.generatedAt);
 const sheet=(name:string,rows:(string|number|boolean)[][])=>{const out=book.addWorksheet(name);out.addRows(rows.map(row=>row.map(value=>typeof value==='string'&&value.length>32767?tr('长文本见完整快照数据'):value)));out.views=[{state:'frozen',ySplit:1}];out.getRow(1).font={bold:true};out.columns.forEach(column=>column.width=26);out.eachRow(row=>row.alignment={vertical:'top',wrapText:true});return out;};
 sheet(tr('报表信息'),[[tr('字段'),tr('值')],[tr('快照编号'),snapshot.snapshotId],[tr('项目'),c.project],[tr('语言'),packet.language],[tr('统计范围'),c.reportScope.nodeIds.map(id=>packet.objects[id]||id).join(' / ')],[tr('关注能源'),packet.objects[c.focusCategoryId]||c.focusCategoryId],[tr('项目时区'),c.projectTimeZone],[tr('开始时间'),c.time.from],[tr('结束时间'),c.time.to],[tr('查询截止'),c.asOf],[tr('末次数据观察（非完整截止）'),snapshot.provenance.sourceLastObservedAt||'—'],[tr('快照生成'),snapshot.generatedAt],[tr('历史读取观察区间'),snapshot.provenance.historyObservedFrom+' / '+snapshot.provenance.historyObservedTo],[tr('状态观察'),snapshot.modules.issues?.data?.stateObservedAt||'—'],[tr('配置指纹'),snapshot.provenance.configFingerprint],[tr('同期比较'),JSON.stringify(c.comparison||{})],[tr('说明'),tr('空值、NA 和真实零分别保留。各报告独立，不相加；完整依据见快照数据。')],[tr('说明'),tr('页面数值按显示精度呈现，可能存在微小尾差；Excel 和 JSON 保留未舍入的计算值。')]]);
 if(snapshot.diagnostics)sheet(tr('诊断返回范围'),[[tr('说明'),diagnosticSummary(snapshot.diagnostics,(key,...values)=>translateFor(packet.language,key,...values))],[tr('全包诊断总预算'),snapshot.diagnostics.rowBudget],[tr('全包已返回诊断数'),snapshot.diagnostics.returnedCount],[],diagnosticHeaders((key,...values)=>translateFor(packet.language,key,...values)),...diagnosticRows(snapshot.diagnostics,undefined,(key,...values)=>translateFor(packet.language,key,...values))]);
 sheet(tr('核心经营指标'),[[tr('指标'),tr('能源类型'),tr('值'),tr('单位'),tr('数据质量'),tr('统计口径'),tr('完整区间用量'),tr('已有用量'),tr('源点')],...(snapshot.modules.kpis?.data?.values||[]).map(metric=>[metric.id,metric.categoryId||'',metric.valueType==='na'?'NA':cell(metric.value),metric.unit,metric.quality,metric.valueBasis,cell(metric.completeValue),cell(metric.knownValue),metric.sourceIds.join(', ')])]);
 for(const [index,table]of cockpitExportTables(packet).entries()){
  const report=snapshot.reports[table.id],prefix='R'+String(index+1).padStart(2,'0');
  sheet(prefix,[[tr('报表标识'),table.id],[tr('报表类型'),table.kind],[tr('开始时间'),table.from],[tr('结束时间'),table.to],[tr('汇总间隔'),table.period],[],table.headers,...table.rows]);
  sheet(prefix+'-'+tr('时序'),[[tr('对象编号'),tr('对象'),tr('能源类型'),tr('单位'),tr('时间'),tr('值'),tr('数值类型'),tr('数据质量'),tr('已有用量'),tr('已有用量数值类型'),tr('已有用量质量'),tr('完整区间用量'),tr('完整区间数值类型'),tr('完整区间质量'),tr('源点')],...table.series]);
  sheet(prefix+'-'+tr('计算依据'),[[tr('字段'),tr('值')],[tr('报表标识'),table.id],...Object.entries({summary:report.summary,extra:report.extra,warnings:report.warnings}).flatMap(([key,value])=>chunks(JSON.stringify(value??null)).map((chunk,index)=>[key+' '+(index+1),chunk]))]);
 }
 sheet(tr('完整快照数据'),[[tr('段号'),tr('文本内容')],...chunks(JSON.stringify(packet)).map((chunk,index)=>[index+1,chunk])]);
 return book;
}
function download(blob:Blob,name:string){const url=URL.createObjectURL(blob),anchor=document.createElement('a');anchor.href=url;anchor.download=name;anchor.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
const filename=(packet:CockpitExport,ext:string)=>('EnerCubix_'+packet.snapshot.context.project+'_'+packet.snapshot.snapshotId+'.'+ext).replace(/[\\/:*?"<>|]/g,'_');
export async function exportCockpitXlsx(packet:CockpitExport){const book=await cockpitWorkbook(packet);download(new Blob([await book.xlsx.writeBuffer() as BlobPart],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}),filename(packet,'xlsx'));}
export function exportCockpitJson(packet:CockpitExport){download(new Blob([JSON.stringify(packet,null,2)],{type:'application/json'}),filename(packet,'json'));}

/** Printed diagnostics use exact dataset references; fullJSON/XLSX retain raw intervals. */
export function cockpitPrintEvidence(packet:CockpitExport){
 const definitions:Record<string,unknown>={},seen=new Map<string,string>();
 const diagnostics=(value:unknown,path:string,parent:Record<string,unknown>={},key=''):unknown=>{
  if(Array.isArray(value)){
   const cleaningDetails=key==='details'&&('profileId' in parent||'profileVersion' in parent);
   const refKey=({intervals:'intervalsDiagnosticRef',sourceUsage:'sourceUsageDiagnosticRef',periods:'periodsDiagnosticRef',details:'detailsDiagnosticRef'} as Record<string,string>)[key],ref=refKey?parent[refKey]:undefined,entry=typeof ref==='string'?packet.snapshot.diagnostics?.entries.find(entry=>entry.id===ref):undefined;
   if(entry)return {datasetRef:path,diagnosticRef:entry.id,returnedCount:entry.returnedCount,totalCount:entry.totalCount,truncated:entry.truncated,reason:entry.reason,grain:entry.grain,requestRange:entry.requestRange,returnedRange:entry.returnedRange,fullEvidence:'returnedSnapshotJSONorXLSX'};
   if(key==='intervals'||key==='sourceUsage'||cleaningDetails){const count=key==='intervals'?parent.intervalCount:key==='sourceUsage'?parent.sourceUsageRowCount:parent.detailsCount;return {datasetRef:path,returnedCount:value.length,totalCount:typeof count==='number'?count:null,truncated:typeof parent.sourceUsageTruncated==='boolean'?parent.sourceUsageTruncated:typeof parent.detailsTruncated==='boolean'?parent.detailsTruncated:null,reason:parent.truncationReason??null,fullEvidence:'returnedSnapshotJSONorXLSX'};}
   return value.map((item,index)=>diagnostics(item,path+'['+index+']'));
  }
  return value&&typeof value==='object'?Object.fromEntries(Object.entries(value).map(([key,item])=>[key,diagnostics(item,path+'.'+key,value as Record<string,unknown>,key)])):value;
 };
 const evidence=(value:unknown,path:string)=>{const text=JSON.stringify(value);if(!text||text.length<160)return value;let id=seen.get(text);if(!id){id='E'+(seen.size+1);seen.set(text,id);definitions[id]=diagnostics(value,path);}return {evidenceRef:id};};
 const snapshot=packet.snapshot;
 return {diagnostics:snapshot.diagnostics?{schemaVersion:1,rowBudget:snapshot.diagnostics.rowBudget,returnedCount:snapshot.diagnostics.returnedCount,truncated:snapshot.diagnostics.truncated,entriesRef:'diagnostic-return-scope'}:undefined,boundary:snapshot.boundary,provenance:diagnostics(snapshot.provenance,'snapshot.provenance'),quality:diagnostics(snapshot.quality,'snapshot.quality'),limitations:snapshot.limitations,metrics:diagnostics(snapshot.modules.kpis?.data?.values,'snapshot.modules.kpis.data.values'),reports:Object.fromEntries(Object.entries(snapshot.reports).map(([id,report])=>[id,{rows:report.rows.map((row,index)=>Object.fromEntries(Object.entries(row).map(([key,value])=>[key,evidence(value,'snapshot.reports['+JSON.stringify(id)+'].rows['+index+'].'+key)]))),summary:report.summary,extra:Object.fromEntries(Object.entries(report.extra||{}).map(([key,value])=>[key,evidence(value,'snapshot.reports['+JSON.stringify(id)+'].extra.'+key)])),warnings:report.warnings}])),definitions};
}
