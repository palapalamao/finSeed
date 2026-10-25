import {locale,t} from './i18n';
import {cleaningModeNames} from './cleaning';
import {names} from './types';
import type {EnerCubixRecord} from './types';

export interface ChangeDetail {field:string;before:unknown;after:unknown}
export interface ChangeMessage {
 id:string;ts:string;action:'created'|'updated'|'deleted';category:'relationship'|'source'|'configuration';
 objectId:string;objectName:string;objectKind:string;actor?:string;changes:ChangeDetail[];detailsRestricted?:boolean;
}
export interface ChangeMessagePage {items:ChangeMessage[];total:number;offset:number;limit:number}

export function changeCategoryLabel(category:string){return ({relationship:t('关系变更'),source:t('来源变更'),configuration:t('配置变更')} as Record<string,string>)[category]||t('配置变更');}
export function changeActionLabel(action:string){return ({created:t('新增记录'),updated:t('更新记录'),deleted:t('删除记录')} as Record<string,string>)[action]||action;}
export function changeFieldLabel(field:string){
 if(field==='kind')return t('对象类型');
 if(field==='canonicalId')return t('主档案');
 if(field==='alarmLimits')return t('报警阈值明细');
 if(field==='limit')return t('阈值');
 return ({name:t('名称'),alias:t('显示名称'),meterParentId:t('上级表计'),parentId:t('上级节点'),spaceId:t('空间归属'),organizationId:t('组织归属'),pointId:t('主能耗点'),historyPointId:t('用量历史点'),expressionId:t('计算表达式'),numeratorId:t('供能量对象'),denominatorId:t('输入能耗对象'),categoryId:t('能源类型'),subcategoryId:t('能源子类'),utilityId:t('分项'),tariffId:t('费率'),autoSum:t('按分表自动求和'),includeInTotals:t('计入合计'),historyMode:t('历史类型'),unit:t('单位'),maximum:t('用量上限'),cleaningEnabled:t('启用数据清洗'),cleaningProfileId:t('清洗方案'),formula:t('公式'),variables:t('变量'),parameters:t('清洗参数'),mode:t('处理方式'),enabled:t('启用'),alarmEnabled:t('启用报警'),alarmLimit:t('报警阈值'),coalFactor:t('标准煤系数'),co2Factor:t('碳排放系数'),deltaMin:t('最小增量（deltaMin）'),deltaMax:t('最大增量（deltaMax）'),timeMax:t('最大读数间隔（timeMax）'),derivMin:t('最小变化率（derivMin）'),derivMax:t('最大变化率（derivMax）'),defNull:t('过滤异常（defNull）'),defVal:t('异常替代值（defVal）'),removeNA:t('移除原始 NA（removeNA）'),hisTotalizedRollover:t('计数周期（hisTotalizedRollover）')} as Record<string,string>)[field]||field;
}
const referenceFields=new Set(['parentId','meterParentId','spaceId','organizationId','pointId','historyPointId','expressionId','numeratorId','denominatorId','categoryId','subcategoryId','utilityId','tariffId','cleaningProfileId','canonicalId']);
export function changeValue(field:string,value:unknown,records:EnerCubixRecord[]):string{
 if(value===null||value===undefined)return t('未设置');
 if(typeof value==='boolean')return value?t('开启'):t('关闭');
 if(Array.isArray(value))return value.map(item=>changeValue(field,item,records)).join(locale==='zh-CN'?'、':', ');
 if(typeof value==='object'){
  const object=value as Record<string,unknown>;
  if(object.type==='na')return 'NA';
  if(object.type==='number'&&typeof object.value==='number')return [String(object.value),object.unit?String(object.unit):''].filter(Boolean).join(' ');
  return Object.entries(object).map(([key,item])=>`${field==='variables'?key:changeFieldLabel(key)}: ${changeValue(field==='variables'?'pointId':key,item,records)}`).join(t('；'));
 }
 if(referenceFields.has(field)&&typeof value==='string')return records.find(record=>record.id===value)?.name||value;
 if(field==='kind'&&typeof value==='string')return names[value as keyof typeof names]||value;
 if(field==='mode'&&typeof value==='string'&&value in cleaningModeNames)return cleaningModeNames[value as keyof typeof cleaningModeNames];
 return String(value);
}
