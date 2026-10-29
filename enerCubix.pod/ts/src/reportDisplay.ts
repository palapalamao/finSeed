import {locale,serverMessage,t} from './i18n';
import {meterOrigin,meterOriginLabel} from './meterOrigin';
import dayjs from 'dayjs';
import utc from 'dayjs/plugin/utc';
import {dimensionNames} from './types';
import {reportQualityText} from './reportQuality';
import {cleaningReason,cleaningScopeText} from './cleaning';
import type {FinPoint,ReportDisplay,ReportResult,ReportSnapshot,EnerCubixRecord,Series} from './types';

dayjs.extend(utc);

const cleaningIntervalLabels={intervalStart:t('区间开始'),intervalEnd:t('区间结束（不含）')};

export const reportLabels:Record<string,string>={nodeType:t("节点类型"),parentId:t("上级表计"),focusId:t("当前计量对象"),rootIds:t("总表"),hasChildren:t("包含下级表计"),balanceQuality:t("计量平衡质量"),energyFlow:t("能流图"),nodes:t("计量节点"),links:t("能流连线"),unassigned:t("待确认计量关系"),source:t("上级表计"),target:t("下级表计"),meterCount:t("表计数量"),unassignedCount:t("未归属表计数量"),forecastDays:t("预测天数"),trainingDays:t("训练天数"),forecastRolling:t("滚动训练截止日"),forecasts:t("预测摘要"),backtests:t("历史留出回测"),modelScores:t("候选模型回测"),forecastFrom:t("预测开始"),algorithm:t("算法版本"),phase:t("数据阶段"),model:t("模型"),status:t("状态"),predictedTotal:t("预测合计"),mae:t("回测 MAE"),wape:t("回测 WAPE (%)"),baselineMae:t("上周同期 MAE"),backtestDays:t("回测天数"),validDays:t("有效训练日"),coverage:t("历史完整率 (%)"),trainingEnd:t("训练截止（不含）"),simulated:t("包含模拟历史"),errorRange:t("每日误差参考半宽"),lower:t("预测参考下限"),upper:t("预测参考上限"),prediction:t("回测预测值"),absoluteError:t("绝对误差"),index:t("日序号"),origin:t("训练天数"),baselineId:t("基准对象"),comparisonBaselineId:t("基准对象"),comparisonBaselineName:t("基准名称"),referenceId:t("基准对象"),referenceName:t("基准名称"),percentageQuality:t("变化率质量"),key:t("序号"),id:t("对象"),name:t("对象"),node:t("对象"),nodeId:t("计量对象"),category:t("能源类型"),categoryId:t("能源类型"),utility:t("分项"),utilityId:t("分项"),ts:t("时间"),date:t("日期"),time:t("时间"),value:t("值"),energy:t("能耗"),cost:t("费用"),coal:t("标准煤"),co2:t("碳排放"),unit:t("单位"),quality:t("数据质量"),area:t("面积"),total:t("合计"),ratio:t("占比"),percentage:t("占比 (%)"),rank:t("排名"),sourceIds:t("源点"),current:t("本期"),previous:t("对比期"),change:t("变化"),baseline:t("基准"),actual:t("实际"),x:'X',y:'Y',cop:'COP',working:t("工作时段"),nonWorking:t("非工作时段"),slope:t("斜率"),intercept:t("截距"),r2:t("决定系数 R²"),details:t("范围内表计明细"),scopeId:t("统计范围"),counted:t("实际计入合计"),scopeTotals:t("范围总量"),normalizationArea:t("面积归一化分母"),dimension:t("分析维度"),spacePath:t("空间路径"),meterPath:t("计量路径"),organizationPath:t("组织路径"),parentMeterId:t("上级表计"),included:t("计入合计"),reference:t("对比期"),difference:t("差值"),submeter:t("分表合计"),branchId:t("分表"),leakBranches:t("分表逐期明细"),leakTotals:t("总分表平衡汇总"),nonworking:t("非工作时段"),workingPercentage:t("工作用能占比 (%)"),workingQuality:t("工作用能质量"),nonworkingQuality:t("非工作用能质量"),hour:t("小时"),samples:t("样本数"),aggregation:t("汇总口径"),n:t("有效样本数"),totals:t("区间汇总"),overview:t("概览汇总"),comparisons:t("同期比较"),grandTotals:t("跨能源总览"),fitLine:t("拟合曲线端点"),utilityShares:t("分项占比"),band:t("尖峰谷平时段"),loadBands:t("尖峰谷平区间总量（非日均）"),loadBandsAggregation:t("尖峰谷平汇总口径"),nodeIds:t("分析对象"),referenceIds:t("参考点"),from:t("开始时间"),to:t("结束时间"),period:t("汇总间隔"),metric:t("指标"),kind:t("报表类型"),perArea:t("按面积归一化")};
Object.assign(reportLabels,cleaningIntervalLabels,{cleaning:t('数据清洗'),profileId:t('清洗方案'),profileVersion:t('方案版本'),profileSnapshot:t('方案快照'),parameters:t('清洗参数'),inputCount:t('原始读数数'),intervalCount:t('区间数'),filteredCount:t('过滤数'),substitutedCount:t('替代数'),naCount:t('NA 数'),validCount:t('有效数'),pointId:t('源点'),valueType:t('数值类型'),deltaMin:t('最小增量（deltaMin）'),deltaMax:t('最大增量（deltaMax）'),timeMax:t('最大读数间隔（timeMax）'),derivMin:t('最小变化率（derivMin）'),derivMax:t('最大变化率（derivMax）'),defNull:t('过滤异常（defNull）'),defVal:t('异常替代值（defVal）'),removeNA:t('移除原始 NA（removeNA）'),hisTotalizedRollover:t('计数周期（hisTotalizedRollover）'),reason:t('原因'),rule:t('规则'),rawValue:t('原始值'),cleanedValue:t('清洗后值'),mode:t('清洗模式'),type:t('数值类型')});
Object.assign(reportLabels,{outputCount:t('输出读数数'),nullCount:t('空值数'),rejectedCount:t('拒绝数'),rolloverCount:t('回绕数'),removedNACount:t('已移除 NA 数'),detailsTruncated:t('诊断明细已截断'),processingScope:t('处理次数口径'),sourceIds:t('源点'),sources:t('子表清洗摘要'),externalFunctionManaged:t('外部函数管理'),function:t('历史清洗函数')});
Object.assign(reportLabels,{previousValue:t('前一读数'),emitted:t('是否输出'),substituted:t('是否替代'),intervalSeconds:t('区间时长（秒）')});
Object.assign(reportLabels,{knownTotals:t('已有用量小计'),knownValue:t('已有用量'),knownPercentage:t('已有用量占比'),knownValueType:t('已有用量数值类型'),knownQuality:t('已有用量质量'),completeValue:t('完整区间用量'),completeValueType:t('完整区间数值类型'),completeQuality:t('完整区间质量'),knownUsage:t('已有用量覆盖明细'),basis:t('统计口径'),intervals:t('原始用量区间'),coveredSeconds:t('有数值覆盖秒数'),bucketEnd:t('展示时段结束')});
Object.assign(reportLabels,{profileStatistics:t('已有数据统计'),strictTotal:t('完整区间总量'),average:t('已有数据平均'),peak:t('已有数据最高'),peakAt:t('已有数据最高时段'),valid:t('有数值时段数'),complete:t('完整时段数'),partial:t('部分时段数'),missing:t('缺测时段数'),na:t('NA 时段数'),unfinished:t('未结束且暂无数值的时段数'),ongoing:t('尚未结束的时段数'),expected:t('查询时段数')});
reportLabels.sourceUsage=t('源点用量覆盖');
Object.assign(reportLabels,{balanceMode:t('平衡判断口径'),lossEligible:t('可用于泄漏判断'),totalQuality:t('总表用量质量'),submeterQuality:t('分表合计质量'),meterHistorySegments:t('历史关系分段'),segmentCount:t('分段数量')});
Object.assign(reportLabels,{activeSeconds:t('纳入时长（秒）'),removed:t('是否已移除'),periods:t('覆盖时段与缺口')});
Object.assign(reportLabels,{asOf:t('数据截止'),usageBasis:t('用量显示口径'),usagePolicy:t('计算条件'),selectionTotals:t('范围已有用量合计（已去重）'),usageCoverage:t('对象覆盖情况'),scopeQuality:t('范围归属与计量关系'),meterIds:t('有效表计集合'),scopeDimension:t('选择视角'),scopeNodeIds:t('原选对象'),selectionScope:t('原选择范围'),coverageStart:t('有数据起始'),coverageEnd:t('有数据结束'),expectedSeconds:t('查询时长（秒）'),knownSamples:t('有数值样本数'),knownCurrent:t('本期已有用量'),knownReference:t('对比期已有用量'),currentCoverage:t('本期覆盖率'),referenceCoverage:t('对比期覆盖率'),knownWorking:t('工作时段已有用量'),knownNonworking:t('非工作时段已有用量'),comparability:t('可比性'),percentageBasis:t('占比口径'),rankBasis:t('排名口径'),completeCurrent:t('完整本期用量'),completeReference:t('完整对比期用量'),completePercentage:t('完整范围占比'),completeWorking:t('完整工作时段用量'),completeNonworking:t('完整非工作时段用量'),topologyActiveSeconds:t('已确认关系时长（秒）')});
Object.assign(reportLabels,{knownTotal:t('总表已有用量'),knownSubmeter:t('参与时段分表已有合计'),knownTotalQuality:t('总表已有用量质量'),knownSubmeterQuality:t('参与时段分表合计质量'),membershipQuality:t('参与关系状态'),participationQuality:t('分表参与状态'),leakOwnUsage:t('各表自身已有用量'),masterId:t('对照总表')});
Object.assign(reportLabels,{availableDifference:t('已有用量差值（总表 − 分表）'),availableDifferencePercentage:t('已有用量差值比例 (%)')});
Object.assign(reportLabels,{legacyMembership:t('旧关系恢复范围'),proofId:t('恢复记录'),childId:t('分表')});
Object.assign(reportLabels,{graphId:t('图标识'),objectId:t('分析对象'),relationKind:t('关系类型'),contributionMemberIds:t('贡献成员'),sharedMemberIds:t('共享成员'),additive:t('纯加法分类'),boundaryQuality:t('统计边界质量'),canAdd:t('可直接相加'),memberIds:t('参与成员'),sharedMembers:t('共享引用'),unionValue:t('去重贡献合计'),unionQuality:t('去重质量'),objectIds:t('引用对象'),energyFlowGraphs:t('对象能流图'),energyFlowAccounting:t('范围统计依据')});
Object.assign(reportLabels,{costBasis:t('费用计价依据'),forecastBasis:t('预测依据'),forecastMeterIds:t('预测去重表计'),forecastTotals:t('范围预测费用合计（已去重）'),tariffSnapshot:t('费率快照'),rate:t('单价 (元/能源单位)'),rules:t('时段规则'),exceptions:t('例外费率'),blocks:t('阶梯'),startHour:t('起始小时'),endHour:t('结束小时'),weekday:t('星期'),mod:t('配置版本')});
export function reportLabel(snapshot:ReportSnapshot,key:string){if(snapshot.request.metric==='cost'){const label:Record<string,string>={usageBasis:t('费用显示口径'),knownTotals:t('已有费用小计'),knownValue:t('已有费用'),completeValue:t('完整区间费用'),selectionTotals:t('范围已有费用合计（已去重）'),knownCurrent:t('本期已有费用'),knownReference:t('对比期已有费用'),knownWorking:t('工作时段已有费用'),knownNonworking:t('非工作时段已有费用'),costBasis:t('费用计价依据'),forecastBasis:t('预测依据'),forecastMeterIds:t('预测去重表计')};if(label[key])return label[key];}if(snapshot.result.kind==='energyFlow'&&key==='basis')return t('统计依据');if(snapshot.result.kind==='energyFlow'&&key==='knownSubmeter')return t('下级已有用量小计');if(snapshot.result.kind==='energyFlow'&&key==='knownSubmeterQuality')return t('下级已有量质量');if(snapshot.result.kind==='energyFlow'&&key==='complete')return t('是否完整');if(snapshot.result.kind==='energyFlow'&&key==='coveredSeconds')return t('有效时长（秒）');const objects=snapshot.request.kind==='comparison'&&!snapshot.request.otherFrom;return (objects?({current:t("对象用量"),reference:t("基准用量"),difference:t("差值（对象 − 基准）"),percentage:t("相对基准变化率 (%)")} as Record<string,string>)[key]:undefined)||reportLabels[key]||key;}
export const numberText=(value:number)=>new Intl.NumberFormat(locale,{maximumFractionDigits:2,useGrouping:false}).format(value);
export function displaySeriesName(series:Series):string{
 const suffix=series.role==='history'?' · 历史':series.role==='forecast'?' · 预测':'';
 return suffix&&series.name.endsWith(suffix)?series.name.slice(0,-suffix.length)+t(suffix):series.name;
}
export function buildReportDisplay(records:EnerCubixRecord[],points:FinPoint[]=[]):ReportDisplay{
 const objects:Record<string,string>={},sources:Record<string,string>={},meterKinds:Record<string,string>={};
 for(const r of records){if(r.id){objects[r.id]=r.name;meterKinds[r.id]=r.kind;}if(r.kind==='nativePoint'&&typeof r.nativeSourceId==='string'&&typeof r.nativeDis==='string')sources[r.nativeSourceId]=r.nativeDis;}
 for(const point of points)sources[point.id]=sources[point.id]||point.name;
 return {objects,sources,meterKinds,meterOrigins:Object.fromEntries(records.filter(row=>row.id&&row.kind==='totalMeter').map(row=>[row.id!,meterOrigin(row)])),sourceHistory:Object.fromEntries(points.map(point=>[point.id,point]))};
}
export function reportSourceIds(result:ReportResult):string[]{
 const ids=new Set<string>();const visit=(value:unknown,key='')=>{if(key==='sourceIds'&&Array.isArray(value)){value.forEach(id=>{if(typeof id==='string')ids.add(id);});}else if(Array.isArray(value))value.forEach(item=>visit(item));else if(value&&typeof value==='object')Object.entries(value).forEach(([k,v])=>visit(v,k));};visit(result);return [...ids];
}
export async function reportPointNames(result:ReportResult,_records:EnerCubixRecord[],find:(id:string)=>Promise<{items:FinPoint[]}>):Promise<FinPoint[]>{
 const missing=reportSourceIds(result);const points:FinPoint[]=[];
 for(let offset=0;offset<missing.length;offset+=8)points.push(...(await Promise.all(missing.slice(offset,offset+8).map(async id=>{try{return (await find(id)).items.filter(point=>point.id===id);}catch{return [];}}))).flat());
 return points;
}
function referenceName(snapshot:ReportSnapshot,id:string,key:string):string{
 if(key==='sourceIds'||key==='sourceId')return snapshot.display?.sources[id]||t("源点名称不可用");
 const names=id.split('|').map(part=>snapshot.display?.objects[part]||snapshot.display?.sources[part]).filter(Boolean);
 return snapshot.display?.objects[id]||snapshot.display?.sources[id]||names.join(' / ')||(key==='categoryId'?t("能源类型名称不可用"):t("对象名称不可用"));
}
Object.assign(reportLabels,{relationBasis:t('关系计算依据')});
Object.assign(reportLabels,{referenceOnly:t('仅作汇总参考'),distributionComparable:t('下级分布可比'),energyFlowCoveredScopes:t('已合并下级范围')});
Object.assign(reportLabels,{utilityMembers:t('分项表计明细'),utilityName:t('所属分项'),memberIds:t('分项成员'),flowMode:t('能流展示方式')});
Object.assign(reportLabels,{comparisonBasis:t('比较依据'),comparisonMembers:t('临时比较分表'),comparisonScopes:t('已解析比较范围'),availableMembers:t('可选分表'),defaultMemberIds:t('默认分表'),selectedMemberIds:t('已选分表'),via:t('解析路径'),limitations:t('范围限制')});
Object.assign(reportLabels,{comparisonUnion:t('物理分表并集合计（已去重）'),completeSelection:t('完整边界选择')});
export function readableReportValue(snapshot:ReportSnapshot,key:string,value:unknown,context?:Record<string,unknown>):unknown{
 if((key==='comparisonBasis'||key==='basis')&&value==='physicalBoundary')return t('物理计量边界');
 if(key==='comparisonMembers'&&value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([id,ids])=>[referenceName(snapshot,id,'nodeId'),readableReportValue(snapshot,'selectedMemberIds',ids)]));
 if(key==='limitations'&&Array.isArray(value))return value.map(item=>serverMessage(String(item)));
 if(key==='via'&&Array.isArray(value))return value.map(id=>referenceName(snapshot,String(id),'nodeId')).join(' / ');
 if(key==='relationBasis'&&value==='current')return t('当前关系');
 if(key==='utilityName'&&context&&!context.utilityId)return t('未指定分项');
 if(key==='utilityId'&&value==='')return t('未指定分项');
 if(key==='name'&&snapshot.result.kind==='utility'&&context?.utilityId===''&&!context.nodeId)return t('未指定分项');
 if(key==='percentageBasis'&&value==='areaNormalized')return t('面积归一化结果用于强度对比，不计算分项占比。');
 if(key==='flowMode')return value==='endUse'?t('按能耗分项'):t('按当前关系');
 if(value===null||value===undefined)return value;
 if(snapshot.request.metric==='cost'&&value==='knownUsage'&&['usageBasis','rankBasis','percentageBasis'].includes(key))return t(key==='rankBasis'?'已有费用排名':key==='percentageBasis'?'已有费用占比':'已有费用');if(key==='costBasis')return t('按费率快照逐表计计价；时段费率按闭合主点区间起点，不摊分；阶梯费率要求完整周期基线。');if(key==='forecastBasis')return t('历史逐表计费用模式，未包含未来费率调整');if(['usageBasis','usagePolicy','percentageBasis','rankBasis','comparability'].includes(key))return ({knownUsage:key==='percentageBasis'?t('已有用量占比'):key==='rankBasis'?t('已有用量排名'):t('已有用量'),complete:t('完整可比'),incompleteCoverage:t('覆盖不完整，不计算可比指标'),overlappingScopes:t('范围重叠，保留各对象用量，不计算占比'),zeroKnownTotal:t('已有用量合计为零，无法计算占比'),noKnownUsage:t('没有可用于占比的已有用量'),negativeConsumption:t('存在负用量，无法计算占比'),incompatibleBaseline:t('基准的能源类型或单位不一致'),missingCalendar:t('未配置工作日历'),billingRequiresCompleteCoverage:t('费用按费率规则计算；缺测或阶梯基线不足时不生成完整账单。'),completeTrainingHistoryRequired:t('预测仅使用满足完整率和回测条件的训练历史。'),completePairsRequired:t('回归只使用有效且完整的成对观测。'),comparableCoverageRequired:t('效率、比率与损耗需要完整且可比较的数据覆盖。')} as Record<string,string>)[String(value)]||value;
 if(key==='proofId')return value;
 if(key==='basis'&&value==='snapshotRecovered')return t('按旧备份恢复');
 if(key==='balanceMode')return ({independent:t('独立计量平衡'),consistency:t('计算一致性检查'),mixed:t('混合计算口径'),unknown:t('未知历史关系')} as Record<string,string>)[String(value)]||value;
 if(['complete','removed','completeSelection','referenceOnly','distributionComparable'].includes(key))return value===true?t('是'):t('否');
 if(['coverage','currentCoverage','referenceCoverage'].includes(key)&&typeof value==='number')return numberText(value*100)+'%';
 if(key==='lossEligible')return value===true?t('是'):t('否');
 if(key==='processingScope')return cleaningScopeText(value);
 if(key==='basis'&&value==='closedSourceIntervals')return t('仅统计查询范围内已闭合的原始用量区间');
 if(key==='reason')return cleaningReason(String(value));
 if(key==='rule')return reportLabels[String(value)]||String(value);
 if(key==='unit'&&typeof value==='string')return t(value);
 if(key==='band')return ({sharp:t('尖时'),peak:t('峰时'),flat:t('平时'),valley:t('谷时'),mixed:t('混合时段'),unknown:t('未分类')} as Record<string,string>)[String(value)]||value;
 if((key==='valueType'||key.endsWith('ValueType')||key==='type')&&value==='na')return 'NA';
 if((key==='valueType'||key.endsWith('ValueType')||key==='type')&&value==='number')return t('数值');
 if((key==='valueType'||key.endsWith('ValueType')||key==='type')&&value==='null')return t('空值');
 if(key==='mode')return ({drop:t('过滤异常'),replace:t('替代异常'),rollover:t('累计表回绕')} as Record<string,string>)[String(value)]||value;
 if(['defNull','removeNA'].includes(key)&&typeof value==='boolean')return value?t('启用'):t('关闭');
 if((key==='id'||key.endsWith('Id'))&&typeof value==='string')return referenceName(snapshot,value,key);
 if(key.endsWith('Ids')&&Array.isArray(value))return value.map(id=>referenceName(snapshot,String(id),key)).join('、');
 if(key==='model')return ({meterSum:t('逐表计费用模型汇总'),seasonalNaive:t("上周同期"),weekdayMean:t("近期同星期均值"),dampedTrend:t("周周期＋衰减趋势")} as Record<string,string>)[String(value)]||value;
 if(key==='phase')return value==='forecast'?t("预测"):t("历史");
 if(key==='simulated'||key==='forecastRolling'||key==='detailsTruncated'||key==='externalFunctionManaged'||key==='emitted'||key==='substituted')return value===true?t("是"):t("否");
 if(key==='nodeType')return ({meter:t("表计"),space:t('空间'),organization:t('组织'),utility:t('分项'),summary:t("统计汇总"),difference:t("计量差额")} as Record<string,string>)[String(value)]||value;
 if(key==='hasChildren'||key==='additive'||key==='canAdd')return value===true?t("是"):t("否");
 if(snapshot.result.kind==='energyFlow'&&key==='basis')return ({endUse:t('按能耗分项'),metering:t('当前计量关系'),calculation:t('公式引用'),space:t('空间能耗分布'),organization:t('组织能耗分布'),physicalBoundary:t('计量边界'),classificationUnion:t('分类成员并集'),unavailable:t('无统一统计边界')} as Record<string,string>)[String(value)]||t('统计依据不可用');
 if(snapshot.result.kind==='energyFlow'&&key==='relationKind')return ({metering:t('当前计量关系'),calculation:t('公式引用'),grouping:t('统计归属')} as Record<string,string>)[String(value)]||t('关系类型未知');
 if(snapshot.result.kind==='energyFlow'&&(key==='boundaryQuality'||key==='unionQuality')&&!['ok','good','derived','estimated','filtered','substituted','missing','incompleteInterval'].includes(String(value)))return value==='overlappingScopes'?t('来源重叠'):t('贡献范围无法完整解析');
 if((key==='quality'||key==='balanceQuality')&&snapshot.result.kind==='energyFlow')return ({ok:t("正常"),derived:t("计算值"),estimated:t("估算值"),missing:t("缺测"),negativeBalance:t("分表大于总表"),topologyIncomplete:t("计量关系不完整"),topologyUnknown:t('历史计量关系尚未确认'),incompatibleUnit:t("单位不兼容")} as Record<string,string>)[String(value)]||reportQualityText(snapshot,String(value),context);
 if(key==='quality'||key.endsWith('Quality'))return reportQualityText(snapshot,String(value),context);
 if((key==='source'||key==='target')&&snapshot.result.kind==='energyFlow'&&typeof value==='string')return referenceName(snapshot,value,'nodeId');
 if(key==='dimension'||key==='scopeDimension')return dimensionNames[value as keyof typeof dimensionNames]||value;
 if(Array.isArray(value))return value.map(item=>readableReportValue(snapshot,'',item));
 if(typeof value==='object')return Object.fromEntries(Object.entries(value).filter(([k])=>k!=='key').map(([k,v])=>[reportLabel(snapshot,k),readableReportValue(snapshot,k,v,value as Record<string,unknown>)]));
 return value;
}
export function reportCellText(snapshot:ReportSnapshot,key:string,value:unknown,precise=false,context?:Record<string,unknown>):string{
 if((key==='value'||key==='total')&&context?.valueType==='na')return 'NA';
 const readable=readableReportValue(snapshot,key,value,context);
 if(readable===null||readable===undefined)return '—';
 if(typeof readable==='number')return precise?String(readable):numberText(readable);
 if(typeof readable==='object')return JSON.stringify(readable);
 return String(readable);
}
export function compactReportTime(ts:string,period:string):string{
 if(period==='week')return t("{0}月{1}日当周",Number(ts.slice(5,7)),Number(ts.slice(8,10)));
 if(period==='year')return ts.slice(0,4)+(locale==='zh-CN'?'年':'');if(period==='month')return t("{0}年{1}月",ts.slice(0,4),Number(ts.slice(5,7)));
 if(period==='hour')return `${Number(ts.slice(5,7))}/${Number(ts.slice(8,10))} ${ts.slice(11,16)}`;
 return t("{0}月{1}日",Number(ts.slice(5,7)),Number(ts.slice(8,10)));
}
export function leakGroups(snapshot:ReportSnapshot){
 const {result}=snapshot;
 return result.series.map(series=>{const node=series.nodeId||series.id.split('|')[0];const matches=(row:Record<string,unknown>)=>(row.nodeId===node||!row.nodeId&&result.series.length===1)&&(!row.categoryId||row.categoryId===series.categoryId)&&(!row.unit||row.unit===series.unit);const branches=(Array.isArray(result.extra?.leakBranches)?result.extra.leakBranches:[]) as Record<string,unknown>[];const totals=(Array.isArray(result.extra?.leakTotals)?result.extra.leakTotals:[]) as Record<string,unknown>[];return {series,total:totals.find(matches),result:{...result,series:[series],rows:result.rows.filter(matches),extra:{...result.extra,leakBranches:branches.filter(matches)}}};});
}
export function isProfileReference(series:Series,referenceIds:readonly string[]=[]){
 return series.id.endsWith('|reference')||referenceIds.includes(series.nodeId||series.id.split('|')[0]);
}
export function profileGroups(snapshot:ReportSnapshot){
 const groups=new Map<string,{title:string;series:Series[]}>();
 for(const series of snapshot.result.series){const node=series.nodeId||series.id.split('|')[0];const reference=isProfileReference(series,snapshot.request.referenceIds);const role=reference?t("参考曲线"):snapshot.result.kind==='primary'?t("折算对比"):snapshot.request.metric==='cost'?t("费用对比"):t("用量对比");const kind=snapshot.display?.meterKinds[node];const category=series.categoryId?referenceName(snapshot,series.categoryId,'categoryId'):'';const key=`${series.categoryId||''}|${series.unit}|${role}`;const group=groups.get(key)||{title:[category,role,t(series.unit)].filter(Boolean).join(' · '),series:[]};group.series.push(!reference&&(kind==='totalMeter'||kind==='meter')?{...series,name:`${series.name}（${kind==='totalMeter'?(snapshot.display?.meterOrigins?.[node]&&snapshot.display.meterOrigins[node].type!=='unconfirmed'?meterOriginLabel(snapshot.display.meterOrigins[node]):t("总表")):t("分表")}）`}:series);groups.set(key,group);}
 const result=[...groups.values()];
 if(snapshot.result.kind!=='profile')return result;
 const references=snapshot.result.series.filter(series=>isProfileReference(series,snapshot.request.referenceIds));
 const consumption=result.filter(group=>!isProfileReference(group.series[0],snapshot.request.referenceIds));
 // Like SEED, append the selected reference lines to each consumption chart.
 // Retain reference-only results when no consumption series was returned.
 return consumption.length?consumption.map(group=>({...group,series:[...group.series,...references]})):result;
}
export function profileStats(snapshot:ReportSnapshot,series:Series){
 const {from,to}=snapshot.result;const period=snapshot.request.period;const expectedTimes=new Set<number>();
 const zone=from.match(/([+-])(\d{2}):(\d{2})$/);const offset=zone?(zone[1]==='-'?-1:1)*(Number(zone[2])*60+Number(zone[3]))*60000:0;
 const localFrom=dayjs.utc(Date.parse(from)+offset);
 const start=period==='week'?localFrom.startOf('day').subtract((localFrom.day()+6)%7,'day'):localFrom.startOf(period);
 for(let at=start;at.valueOf()-offset<Date.parse(to);at=at.add(1,period))expectedTimes.add(at.valueOf()-offset);
 const reliableQualities=['ok','good','estimated','derived','cleaned','corrected'];
 const byTime=new Map(series.points.map(point=>[Date.parse(point.ts),point]));
 const points=[...byTime.values()].filter(point=>expectedTimes.has(Date.parse(point.ts))).map(point=>({...point,value:'knownValue'in point?point.knownValue??null:point.value})).filter(point=>point.value!==null&&Number.isFinite(point.value));
 const valid=points.length;const numericTimes=new Set(points.map(point=>Date.parse(point.ts)));let complete=0,na=0,unfinished=0,ongoing=0;
 for(const at of expectedTimes){const point=byTime.get(at);const end=point?.bucketEnd?Date.parse(point.bucketEnd):dayjs.utc(at+offset).add(1,period).valueOf()-offset;const pending=end>Date.parse(snapshot.result.asOf||snapshot.request.asOf||snapshot.generatedAt);if(pending)ongoing++;
  const numeric=numericTimes.has(at);
  if(numeric){const strictValue=point&&'completeValue'in point?point.completeValue:point?.value;const strictQuality=point?.completeQuality??point?.quality;const knownQuality=point?.knownQuality??point?.quality;if(strictValue!==null&&strictValue!==undefined&&Number.isFinite(strictValue)&&reliableQualities.includes(strictQuality||'')&&reliableQualities.includes(knownQuality||'')&&at>=Date.parse(from)&&end<=Date.parse(to)&&!pending)complete++;}
  else if((point?.knownValueType??point?.valueType)==='na')na++;else if(pending)unfinished++;
 }
 const totals=(snapshot.result.summary.totals||[]) as {id:string;value:number|null;valueType?:string;quality?:string;completeValue?:number|null}[];
 const knownTotals=(snapshot.result.summary.knownTotals||[]) as typeof totals;const strictTotal=totals.find(row=>row.id===series.id);const knownTotal=knownTotals.find(row=>row.id===series.id);
 const subtotal=valid?points.reduce((sum,point)=>sum+point.value!,0):null;const total=knownTotal?knownTotal.value:snapshot.request.metric==='cost'?strictTotal?.value??null:subtotal;
 const peakPoint=points.reduce<typeof points[number]|undefined>((peak,point)=>!peak||point.value!>peak.value!?point:peak,undefined);
 return {total,valueType:total!==null?'number':knownTotal?.valueType??(na>0?'na':strictTotal?.valueType),quality:knownTotal?.quality??strictTotal?.quality,strictTotal:strictTotal&&'completeValue'in strictTotal?strictTotal.completeValue??null:strictTotal?.value??null,average:subtotal!==null?subtotal/valid:null,peak:peakPoint?.value??null,peakAt:peakPoint?.ts,valid,complete,partial:valid-complete,na,unfinished,ongoing,missing:expectedTimes.size-valid-na-unfinished,expected:expectedTimes.size};
}
