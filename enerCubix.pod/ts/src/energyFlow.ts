import type {ReportResult,ReportSnapshot} from './types';

export interface EnergyFlowNode {
 id:string;
 nodeId?:string;
 name:string;
 nodeType:'meter'|'summary'|'difference'|'space'|'organization'|'utility';
 utilityId?:string;
 memberIds?:string[];
 parentId?:string;
 categoryId:string;
 unit:string;
 value:number|null;
 quality:string;
 sourceIds:string[];
 submeter:number|null;
 difference:number|null;
 balanceQuality:string;
 hasChildren:boolean;
 percentage:number|null;
 balanceMode?:'independent'|'consistency'|'mixed'|'unknown';
 lossEligible?:boolean;
 knownValue?:number|null;
 knownQuality?:string;
 knownValueType?:'number'|'na'|'null';
 knownSubmeter?:number|null;
 knownSubmeterQuality?:string;
 coverage?:number;
 coveredSeconds?:number;
 activeSeconds?:number;
}
export interface EnergyFlowLink {
 source:string;
 target:string;
 value:number;
 quality:string;
 sourceIds:string[];
 percentage:number|null;
 relationKind?:'metering'|'calculation'|'grouping'|'classification';
}
export interface EnergyFlowData {
 graphId?:string;
 objectId?:string;
 basis?:'metering'|'calculation'|'space'|'organization'|'endUse';
 contributionMemberIds?:string[];
 sharedMemberIds?:string[];
 additive?:boolean;
 boundaryQuality?:string;
 categoryId:string;
 unit:string;
 focusId:string;
 rootIds:string[];
 nodes:EnergyFlowNode[];
 links:EnergyFlowLink[];
 unassigned:EnergyFlowNode[];
}
export interface EnergyFlowAccounting {
 canAdd:boolean;memberIds:string[];sharedMemberIds:string[];
 sharedMembers:{meterId:string;objectIds:string[]}[];
 unionValue:number|null;unionQuality:string;basis:'physicalBoundary'|'classificationUnion'|'unavailable';
}
export const energyFlowNodeValue=(node:EnergyFlowNode):number|null=>Object.hasOwn(node,'knownValue')?node.knownValue??null:node.value;
export const energyFlowNodeQuality=(node:EnergyFlowNode):string=>node.knownQuality||node.quality;

export function energyFlowData(result:ReportResult):EnergyFlowData|undefined {
 const data=result.extra?.energyFlow as Partial<EnergyFlowData>|undefined;
 if(!data||typeof data!=='object'||typeof data.categoryId!=='string'||typeof data.unit!=='string'||typeof data.focusId!=='string'||!Array.isArray(data.rootIds)||!Array.isArray(data.nodes)||!Array.isArray(data.links)||!Array.isArray(data.unassigned))return;
 return data as EnergyFlowData;
}
export function energyFlowGraphs(result:ReportResult):EnergyFlowData[]{
 const graphs=result.extra?.energyFlowGraphs;
 if(Array.isArray(graphs))return graphs.flatMap(graph=>{const valid=energyFlowData({...result,extra:{energyFlow:graph}});return valid?[valid]:[];});
 const single=energyFlowData(result);return single?[single]:[];
}
export function energyFlowAccounting(result:ReportResult):EnergyFlowAccounting|undefined{
 const data=result.extra?.energyFlowAccounting as EnergyFlowAccounting|undefined;
 return data&&Array.isArray(data.memberIds)&&Array.isArray(data.sharedMemberIds)&&Array.isArray(data.sharedMembers)?data:undefined;
}
/** Build an independently exportable object graph, without borrowing other graphs' rows. */
export function energyFlowGraphSnapshot(snapshot:ReportSnapshot,graphId:string):ReportSnapshot{
 const graph=energyFlowGraphs(snapshot.result).find(graph=>(graph.graphId||graph.objectId||graph.focusId)===graphId);
 if(!graph)return snapshot;
 const nodes=[...graph.nodes,...graph.unassigned];
 const focus=energyFlowFocus(graph);
 const rows=nodes.map(node=>({...node,graphId,nodeId:node.nodeId||node.id}));
 const series=nodes.map(node=>({id:node.id,nodeId:node.nodeId||node.id,name:node.name,categoryId:node.categoryId,unit:node.unit,points:[{ts:snapshot.result.from,value:energyFlowNodeValue(node),quality:energyFlowNodeQuality(node),sourceIds:node.sourceIds}]}));
 const extra:Record<string,unknown>={...snapshot.result.extra,energyFlow:graph};delete extra.energyFlowGraphs;delete extra.energyFlowAccounting;delete extra.energyFlowOverview;delete extra.energyFlowSegments;
 return {...snapshot,request:{...snapshot.request,nodeIds:[graph.objectId||graph.focusId]},result:{...snapshot.result,rows,series,summary:{value:focus?energyFlowNodeValue(focus):null,unit:graph.unit},extra}};
}

export interface EnergyFlowSegment {
 from:string;
 to:string;
 known:boolean;
 energyFlow:EnergyFlowData;
 rows:ReportResult['rows'];
 series:ReportResult['series'];
 summary:ReportResult['summary'];
 warnings:string[];
 energyFlowOverview?:EnergyFlowOverview;
}
export interface EnergyFlowOverviewRow {
 id:string;nodeId:string;name:string;unit:string;value:number|null;quality:string;complete:boolean;coverage:number;
 activeSeconds:number;coveredSeconds:number;removed:boolean;substituted:boolean;sourceIds:string[];
 periods:{from:string;to:string;value:number|null;quality:string;pointId:string}[];
}
export interface EnergyFlowOverview {from:string;to:string;unknownTopologySeconds:number;rows:EnergyFlowOverviewRow[]}
export function energyFlowOverview(result:ReportResult):EnergyFlowOverview|undefined {
 const value=result.extra?.energyFlowOverview as EnergyFlowOverview|undefined;
 return value&&Array.isArray(value.rows)&&typeof value.unknownTopologySeconds==='number'?value:undefined;
}
export function energyFlowSegments(result:ReportResult):EnergyFlowSegment[]{
 const segments=result.extra?.energyFlowSegments;
 return Array.isArray(segments)?segments.filter((segment:unknown):segment is EnergyFlowSegment=>{
  if(!segment||typeof segment!=='object')return false;
  const value=segment as Partial<EnergyFlowSegment>;
  return typeof value.from==='string'&&typeof value.to==='string'&&typeof value.known==='boolean'&&!!energyFlowData({...result,extra:{energyFlow:value.energyFlow}})&&Array.isArray(value.rows)&&Array.isArray(value.series)&&Array.isArray(value.warnings);
 }):[];
}
export function energyFlowSegmentSnapshot(snapshot:ReportSnapshot,index:number):ReportSnapshot{
 const segment=energyFlowSegments(snapshot.result)[index];if(!segment)return snapshot;
 const extra={...snapshot.result.extra};delete extra.energyFlowSegments;
 delete extra.energyFlowOverview;
 if(segment.energyFlowOverview)extra.energyFlowOverview=segment.energyFlowOverview;
 // A whole-query cleaning summary must not describe a different selected window.
 if(segment.from!==snapshot.result.from||segment.to!==snapshot.result.to)delete extra.cleaning;
 return {...snapshot,request:{...snapshot.request,from:segment.from,to:segment.to},result:{...snapshot.result,from:segment.from,to:segment.to,rows:segment.rows,series:segment.series,summary:segment.summary||{},warnings:segment.warnings,extra:{...extra,energyFlow:segment.energyFlow}}};
}

export function defaultEnergyFlowSegment(result:ReportResult):number{
 if(result.extra?.relationBasis==='current'||Array.isArray(result.extra?.energyFlowGraphs))return -1;
 if(energyFlowOverview(result))return -1;
 const segments=energyFlowSegments(result);let best=-1,duration=-1;
 for(const [index,segment]of segments.entries()){
  const meters=segment.energyFlow.nodes.filter(node=>node.nodeType==='meter');
  const complete=segment.known&&meters.length>0&&meters.every(node=>typeof node.value==='number'&&Number.isFinite(node.value)&&node.value>=0&&['ok','good','derived','estimated','cleaned','corrected'].includes(node.quality));
  const span=Date.parse(segment.to)-Date.parse(segment.from);
  if(complete&&span>=duration){best=index;duration=span;}
 }
 return best>=0?best:Math.max(0,segments.findIndex(segment=>segment.known));
}
export function mergeEnergyFlowGraphSnapshots(snapshot:ReportSnapshot,panels:ReportSnapshot[]):ReportSnapshot{
 if(!panels.length)return snapshot;
 const graphs=panels.map(panel=>energyFlowData(panel.result)!);
 const originals=energyFlowGraphs(snapshot.result);
 const focused=graphs.some((graph,index)=>graph.focusId!==originals[index]?.focusId);
 const extra:Record<string,unknown>={...snapshot.result.extra,energyFlow:graphs[0],energyFlowGraphs:graphs};
 delete extra.energyFlowOverview;delete extra.energyFlowSegments;
 if(focused){delete extra.energyFlowAccounting;delete extra.selectionTotals;delete extra.cleaning;delete extra.knownUsage;}
 return {...snapshot,request:focused?{...snapshot.request,nodeIds:panels.flatMap(panel=>panel.request.nodeIds)}:snapshot.request,result:{...snapshot.result,rows:panels.flatMap(panel=>panel.result.rows),series:panels.flatMap(panel=>panel.result.series),summary:focused?{}:snapshot.result.summary,extra}};
}

// Keep navigation context outside exported report metadata: exports contain only the current scope.
const sourceSnapshots=new WeakMap<ReportSnapshot,ReportSnapshot>();
const finite=(value:number|null):value is number=>typeof value==='number'&&Number.isFinite(value);
export function energyFlowFocus(data:EnergyFlowData):EnergyFlowNode|undefined {
 return data.nodes.find(node=>node.id===data.focusId)||data.nodes.find(node=>node.nodeType==='summary')||data.nodes.find(node=>data.rootIds.includes(node.id));
}
function childMap(nodes:EnergyFlowNode[]) {
 const children=new Map<string,EnergyFlowNode[]>();
 for(const node of nodes)if(node.parentId){const group=children.get(node.parentId)||[];group.push(node);children.set(node.parentId,group);}
 return children;
}
export function energyFlowBreadcrumbs(snapshot:ReportSnapshot):EnergyFlowNode[] {
 const current=energyFlowData(snapshot.result);const original=energyFlowData((sourceSnapshots.get(snapshot)||snapshot).result);
 if(!current||!original)return [];
 const byId=new Map(original.nodes.map(node=>[node.id,node]));const summary=original.nodes.find(node=>node.nodeType==='summary');
 let at=byId.get(current.focusId);const chain:EnergyFlowNode[]=[];const seen=new Set<string>();
 while(at&&!seen.has(at.id)){chain.unshift(at);seen.add(at.id);at=at.parentId?byId.get(at.parentId):undefined;}
 if(summary&&!seen.has(summary.id))chain.unshift(summary);
 return chain;
}
export function energyFlowStats(data:EnergyFlowData) {
 const focus=energyFlowFocus(data);const overview=focus?.nodeType==='summary';
 const byId=new Map(data.nodes.map(node=>[node.id,node]));const roots=data.rootIds.map(id=>byId.get(id));
 let submeter=focus&&Object.hasOwn(focus,'knownSubmeter')?focus.knownSubmeter??null:focus?.submeter??null;
 if(overview){const values=roots.map(root=>root?(root.hasChildren?root.submeter:root.value):null);submeter=values.length&&values.every(finite)?values.reduce((sum,value)=>sum+value,0):null;}
 const total=focus?energyFlowNodeValue(focus):null;
 const difference=overview?(finite(total)&&finite(submeter)?total-submeter:null):focus?.difference??null;
 const count=overview?roots.length:data.nodes.filter(node=>node.nodeType!=='difference'&&node.parentId===focus?.id).length;
 return {total,submeter,difference,count,overview};
}

export function focusEnergyFlowSnapshot(snapshot:ReportSnapshot,focusId?:string):ReportSnapshot {
 const original=sourceSnapshots.get(snapshot)||snapshot;const data=energyFlowData(original.result);
 if(!data)return snapshot;
 const summary=data.nodes.find(node=>node.nodeType==='summary');
 const id=focusId||summary?.id||data.focusId;const focus=data.nodes.find(node=>node.id===id);
 if(!focus||focus.nodeType==='difference')return snapshot;
 if(focus.nodeType==='summary')return original;
 const children=childMap(data.nodes);const ids=new Set<string>();const pending=[focus];
 while(pending.length){const node=pending.pop()!;if(ids.has(node.id))continue;ids.add(node.id);pending.push(...children.get(node.id)||[]);}
 const graph:EnergyFlowData={...data,focusId:focus.id,rootIds:[focus.id],nodes:data.nodes.filter(node=>ids.has(node.id)),links:data.links.filter(link=>ids.has(link.source)&&ids.has(link.target)),unassigned:[]};
 const canonicalIds=new Set(data.nodes.filter(node=>ids.has(node.id)).map(node=>node.nodeId||node.id));
 const inScope=(id:unknown)=>typeof id==='string'&&(ids.has(id)||ids.has(id.split('|')[0])||canonicalIds.has(id));
 const stats=energyFlowStats(graph);
 const result:ReportResult={...original.result,rows:original.result.rows.filter(row=>data.basis?ids.has(String(row.id)):inScope(row.nodeId??row.id)),series:original.result.series.filter(series=>data.basis?ids.has(series.id):inScope(series.nodeId??series.id)),summary:{focusId:focus.id,categoryId:data.categoryId,unit:data.unit,value:stats.total,total:stats.total,submeter:stats.submeter,difference:stats.difference,meterCount:graph.nodes.filter(node=>node.nodeType==='meter').length,unassignedCount:0},extra:{...original.result.extra,energyFlow:graph}};
 const output:ReportSnapshot={...original,request:{...original.request,nodeIds:[focus.nodeId||focus.id]},result};
 sourceSnapshots.set(output,original);return output;
}

export interface EnergyFlowPosition {node:EnergyFlowNode;depth:number;x:number;y:number;height:number;color:string}
export interface EnergyFlowRibbon {link:EnergyFlowLink;path:string;thickness:number;color:string}
export interface EnergyFlowLayout {width:number;height:number;nodes:EnergyFlowPosition[];links:EnergyFlowRibbon[]}
export const energyFlowColors=['#137f7a','#3976ba','#7865af','#bd893b','#538579'];
const differenceColor='#a7b5bf';
export function energyFlowLayout(data:EnergyFlowData):EnergyFlowLayout {
 const focus=energyFlowFocus(data);const width=1100;
 if(!focus)return {width,height:320,nodes:[],links:[]};
 const byId=new Map(data.nodes.map(node=>[node.id,node]));const children=childMap(data.nodes);const visited=new Set<string>();
 type Branch={node:EnergyFlowNode;depth:number;color:string;children:Branch[];height:number;span:number};
 const branches:Branch[]=[];
 const tree=(node:EnergyFlowNode,depth:number,color:string):Branch=>{
  visited.add(node.id);const branch:Branch={node,depth,color:node.nodeType==='difference'?differenceColor:color,children:[],height:0,span:0};branches.push(branch);
  if(depth<2){const next=node.nodeType==='summary'?data.rootIds.map(id=>byId.get(id)).filter((child):child is EnergyFlowNode=>!!child):children.get(node.id)||[];
   for(const [index,child]of next.entries())if(!visited.has(child.id))branch.children.push(tree(child,depth+1,node.nodeType==='summary'||data.basis==='endUse'&&depth===0?energyFlowColors[index%energyFlowColors.length]:color));
  }
  return branch;
 };
 const root=tree(focus,0,energyFlowColors[0]);
 // A single common scale preserves every recorded flow; layout spacing never changes its amount.
 const largest=branches.reduce((max,branch)=>{const value=energyFlowNodeValue(branch.node);return finite(value)?Math.max(max,value):max;},0);const scale=largest>0?280/largest:0;
 const outgoing=new Map<string,number>();for(const link of data.links)if(Number.isFinite(link.value)&&link.value>0)outgoing.set(link.source,(outgoing.get(link.source)||0)+link.value);
 const measure=(branch:Branch):number=>{const value=energyFlowNodeValue(branch.node);branch.height=finite(value)&&value>0?Math.max(value,outgoing.get(branch.node.id)||0)*scale:0;const childSpan=branch.children.reduce((sum,child)=>sum+measure(child),0)+Math.max(0,branch.children.length-1)*20;branch.span=Math.max(48,branch.height,childSpan);return branch.span;};
 measure(root);const nodes:EnergyFlowPosition[]=[];const columns=[20,430,800];
 const position=(branch:Branch,top:number)=>{
  nodes.push({node:branch.node,depth:branch.depth,x:columns[branch.depth],y:top+(branch.span-branch.height)/2,height:branch.height,color:branch.color});
  const childSpan=branch.children.reduce((sum,child)=>sum+child.span,0)+Math.max(0,branch.children.length-1)*20;let next=top+(branch.span-childSpan)/2;
  for(const child of branch.children){position(child,next);next+=child.span+20;}
 };
 position(root,75);const placed=new Map(nodes.map(node=>[node.node.id,node]));const sourceOffsets=new Map<string,number>();const targetOffsets=new Map<string,number>();const links:EnergyFlowRibbon[]=[];
 for(const link of data.links){const source=placed.get(link.source),target=placed.get(link.target);
  if(!source||!target||target.depth!==source.depth+1||!Number.isFinite(link.value)||link.value<=0||source.height<=0||target.height<=0)continue;
  const thickness=link.value*scale;const sx=source.x+14,tx=target.x,sy=source.y+(sourceOffsets.get(link.source)||0),ty=target.y+(targetOffsets.get(link.target)||0),bend=(tx-sx)*.48;
  const path=`M${sx},${sy} C${sx+bend},${sy} ${tx-bend},${ty} ${tx},${ty} L${tx},${ty+thickness} C${tx-bend},${ty+thickness} ${sx+bend},${sy+thickness} ${sx},${sy+thickness}Z`;
  links.push({link,path,thickness,color:target.color});sourceOffsets.set(link.source,(sourceOffsets.get(link.source)||0)+thickness);targetOffsets.set(link.target,(targetOffsets.get(link.target)||0)+thickness);
 }
 return {width,height:Math.max(430,root.span+120),nodes,links};
}
