import {serverMessage,t} from './i18n';
import type {ReportSnapshot} from './types';

const qualityLabels:Record<string,string>={topologyUnknown:t('历史计量关系尚未确认'),invalidCleaningConfiguration:serverMessage('invalidCleaningConfiguration'),missingCleaningProfile:serverMessage('missingCleaningProfile'),missingSource:serverMessage('missingSource'),duplicateSource:serverMessage('duplicateSource'),cycle:serverMessage('cycle'),incompatibleCategory:serverMessage('incompatibleCategory'),cleaned:t("已清洗"),corrected:t("回绕已修正"),filtered:t("有效用量小计"),substituted:t("清洗后用量，含替代值"),na:"NA",ok:t("正常"),good:t("正常"),missing:t("历史读数不足"),estimated:t("估算值"),derived:t("计算值"),predicted:t("预测值"),reset:t("累计读数回退或重置"),negative:t("用量为负值"),historyReadError:t("FIN 历史读取失败"),forbidden:t("无权读取源点历史"),missingInterval:t("未配置历史采集间隔"),notEnergyHistory:t("历史读数类型不适用于能耗计算"),missingArea:t("未配置有效建筑面积"),missingCoefficient:t("未配置折算系数"),missingTariff:t("未配置适用费率"),missingExpression:t("计算公式不存在"),missingBranches:t("未配置分表"),missingMaster:t("未配置总表"),ambiguousMaster:t("存在多个总表，请检查计量关系"),invalidConfiguration:t("计量配置无效"),nativeSourceMissing:t("FIN 原生设备或点位不存在"),incompatibleUnit:t("单位不兼容"),maximum:t("用量超过设定上限")};
qualityLabels.notParticipating=t('此时段未参与');
qualityLabels.snapshotRecovered=t('按旧备份恢复');
qualityLabels.incompleteInterval=t('区间边界未对齐或末段尚未完整');
qualityLabels.cleaned=t('已清洗');
qualityLabels.corrected=t('已修正');
type QualityContext={ts?:unknown;sourceIds?:unknown};
const timeText=(value:string)=>value.replace('T',' ').slice(0,16);

export function qualityLabel(quality:string):string{return qualityLabels[quality]||t("数据异常（{0}）",quality);}

export function reportQualityText(snapshot:ReportSnapshot,quality:string,context?:QualityContext):string{
 if(quality!=='missing'||!context)return qualityLabel(quality);
 const ids=Array.isArray(context.sourceIds)?context.sourceIds.map(String):[];
 const sources=ids.flatMap(id=>snapshot.display?.sourceHistory?.[id]?[snapshot.display.sourceHistory[id]]:[]);
 if(sources.some(point=>!point.his))return t("源点未启用历史记录，请检查 FIN 历史配置");
 // Only hourly usage rows identify an exact boundary here. Other reports retain
 // a general explanation rather than guessing their aggregation semantics.
 if(snapshot.result.kind==='profile'&&snapshot.request.period==='hour'&&typeof context.ts==='string'){
  const start=Date.parse(context.ts);const end=start+3600000;
  const late=sources.find(point=>point.hisStart&&Date.parse(point.hisStart)>start);
  if(late)return t("缺少起始读数：历史从 {0} 开始，请缩短查询范围或检查历史采集。",timeText(late.hisStart!));
  if(end>Date.parse(snapshot.generatedAt)){
   const offset=context.ts.match(/(?:Z|[+-]\d{2}:\d{2})$/)?.[0]||'Z';
   const localEnd=new Date(end+(offset==='Z'?0:(offset[0]==='-'?-1:1)*(Number(offset.slice(1,3))*60+Number(offset.slice(4)))*60000)).toISOString().slice(0,16).replace('T',' ');
   return t("时段尚未结束，请在 {0} 后重新查询。",localEnd);
  }
  const early=sources.find(point=>point.hisEnd&&Date.parse(point.hisEnd)<end);
  if(early)return t("缺少结束读数：最新历史至 {0}，请检查 FIN 历史采集后重新查询。",timeText(early.hisEnd!));
 }
 return t("历史读数不足，无法计算用量；请检查 FIN 历史采集及查询范围。");
}

export function reportWarnings(snapshot:ReportSnapshot):string[]{
 const messages=snapshot.result.warnings.map(warning=>{
  const match=warning.match(/^(.*)\s*[:：]\s*([A-Za-z]+)\s*$/);
  if(!match||!qualityLabels[match[2]])return serverMessage(warning);
  const name=match[1].trim();const quality=match[2];
  const reasons=snapshot.result.series.filter(series=>series.name===name).flatMap(series=>series.points.filter(point=>point.quality===quality&&point.value===null).map(point=>reportQualityText(snapshot,quality,point)));
  return t("{0}：{1}",name,[...new Set(reasons.length?reasons:[qualityLabel(quality)])].join(t("；")));
 });
 return [...new Set(messages)];
}
