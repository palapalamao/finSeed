import type {EChartsCoreOption} from 'echarts/core';
import {palette} from './chartOptions';
import {t} from './i18n';
import {numberText} from './reportDisplay';
import type {ReportSnapshot} from './types';

export type UtilityRow=Record<string,unknown>;
export interface UtilityGroup {key:string;title:string;unit:string;rows:UtilityRow[];members:UtilityRow[];total:number|null;reason:string;partial:boolean}
const numeric=(value:unknown):value is number=>typeof value==='number'&&Number.isFinite(value);
export const utilityName=(row:UtilityRow)=>row.utilityId?String(row.utilityName||row.name||row.utilityId):t('未指定分项');
export function utilityGroups(snapshot:ReportSnapshot):UtilityGroup[]{
 const groups=new Map<string,UtilityGroup>();
 const rows=(Array.isArray(snapshot.result.extra?.utilityShares)?snapshot.result.extra.utilityShares:[]) as UtilityRow[];
 const members=(Array.isArray(snapshot.result.extra?.utilityMembers)?snapshot.result.extra.utilityMembers:[]) as UtilityRow[];
 for(const row of rows){
  const key=`${row.categoryId||''}|${row.unit||''}`;
  if(!groups.has(key))groups.set(key,{key,title:snapshot.display?.objects[String(row.categoryId)]||t('能源类型'),unit:String(row.unit||''),rows:[],members:[],total:null,reason:'',partial:false});
  groups.get(key)!.rows.push(row);
 }
 for(const group of groups.values()){
  group.members=members.filter(row=>`${row.categoryId||''}|${row.unit||''}`===group.key);
  const amounts=group.rows.map(row=>row.value).filter(numeric);
  group.total=amounts.length?amounts.reduce((sum,value)=>sum+value,0):null;
  group.partial=group.members.some(row=>row.complete===false||numeric(row.coverage)&&row.coverage<1||['filtered','incompleteInterval','missing','na'].includes(String(row.quality)));
  const bases=group.rows.map(row=>String(row.percentageBasis||''));
  group.reason=bases.includes('overlappingScopes')?'overlappingScopes':snapshot.request.perArea?'areaNormalized':amounts.some(value=>value<0)||bases.includes('negativeConsumption')?'negativeConsumption':group.total===0?'zeroKnownTotal':!amounts.length?'noKnownUsage':group.rows.some(row=>!Object.hasOwn(row,'utilityId'))?'legacyUtilityShares':group.rows.some(row=>numeric(row.value)&&!numeric(row.percentage))?(bases.find(basis=>basis&&basis!=='knownUsage')||'noKnownUsage'):'';
  if(group.reason==='overlappingScopes'||group.reason==='legacyUtilityShares')group.total=null;
 }
 return [...groups.values()];
}
export function utilityChartOptions(group:UtilityGroup):EChartsCoreOption{
 return {color:palette,animation:false,tooltip:{trigger:'item',renderMode:'richText',formatter:(params:unknown)=>{const data=(params as {data:{name:string;value:number;percentage:number}}).data;return `${data.name}\n${numberText(data.value)} ${t(group.unit)}\n${numberText(data.percentage)}%`;}},legend:{type:'scroll',bottom:0},graphic:[{type:'text',left:'center',top:'34%',style:{text:group.total===null?'—':numberText(group.total),fontSize:24,fontWeight:700,fill:'#173d4b'}},{type:'text',left:'center',top:'44%',style:{text:t(group.unit),fontSize:12,fill:'#58717d'}}],series:[{name:t('所选表计的分项构成'),type:'pie',radius:['48%','68%'],center:['50%','43%'],stillShowZeroSum:false,label:{formatter:(params:unknown)=>{const data=(params as {data:{name:string;value:number;percentage:number}}).data;return `${data.name}\n${numberText(data.value)} ${t(group.unit)} · ${numberText(data.percentage)}%`;}},data:group.reason?[]:group.rows.filter(row=>numeric(row.value)&&numeric(row.percentage)).map(row=>({name:utilityName(row),value:row.value,percentage:row.percentage,utilityId:String(row.utilityId||'')}))}],media:[{query:{maxWidth:480},option:{series:[{radius:['42%','64%'],label:{position:'inside',color:'#fff',fontSize:12,formatter:(params:unknown)=>`${numberText((params as {data:{percentage:number}}).data.percentage)}%`},labelLine:{show:false}}]}}]};
}
export function utilityReason(reason:string){
 return ({overlappingScopes:t('计量范围重叠，相关对象无法计算占比。请取消总表或其下级表，选择互不包含的表计；各表自身用量仍保留。'),areaNormalized:t('面积归一化结果用于强度对比，不计算分项占比。'),negativeConsumption:t('存在负用量，不计算分项占比；请核对表计数据。'),zeroKnownTotal:t('已有用量合计为零，无法计算占比'),noKnownUsage:t('没有可用于占比的已有用量'),legacyUtilityShares:t('此快照使用旧分项口径，请重新查询。')} as Record<string,string>)[reason]||t('没有可用于占比的已有用量');
}
