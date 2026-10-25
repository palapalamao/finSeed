import {t} from './i18n';
import {Alert,Button,Descriptions,Empty,Tag,Typography} from 'antd';
import type {Dimension,FinPoint,EnerCubixRecord} from './types';
import {finEquipUrl,isNativeEquip,mainEnergySources} from './nativeEquip';
import {EnergySourceBadge} from './EnergySourceBadge';
import {names} from './types';
import {MeterOriginBadge} from './MeterOriginBadge';
import {meterOrigin,meterOriginDescription} from './meterOrigin';
import {meterRollupSeconds} from './settings';
import {dimensionPath,isNativeSource,meterDetailCounts} from './dimensionTree';
interface Props {meter?:EnerCubixRecord;records:EnerCubixRecord[];point?:FinPoint;canWrite:boolean;onEdit:(record:EnerCubixRecord)=>void;onJump:(dimension:Dimension,id:string)=>void;onAdmit?:(record:EnerCubixRecord)=>void}
export function MeterDetails({meter,records,point,canWrite,onEdit,onJump,onAdmit}:Props){
 if(!meter)return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description={t("选择表计，查看三种归属与来源")}/>;
 const sourceMeter=meter.kind==='nativePoint'?mainEnergySources(records).get(String(meter.nativeSourceId||meter.id)):undefined;
 const boundPoint=point?.id===meter.pointId?point:undefined;
 const pointName=boundPoint?.navName||boundPoint?.name||records.find(row=>row.kind==='nativePoint'&&(row.nativeSourceId||row.id)===meter.pointId)?.name||String(meter.pointId||t("未绑定"));
 const equipmentId=isNativeEquip(meter)?meter.id:undefined;const finLink=equipmentId?<Button type="link" href={finEquipUrl(equipmentId.split(':')[1]||'',equipmentId)} target="_blank">{t("在 FIN 中打开设备")}</Button>:null;
 if(isNativeSource(meter))return <><div className="meter-detail-heading"><Tag>{meter.kind==='nativePoint'?t("FIN 原点"):'FIN '+String(meter.nativeSourceKind||t("空间"))}</Tag><h3>{meter.name}</h3>{sourceMeter&&<EnergySourceBadge meterName={sourceMeter.name}/>}{isNativeEquip(meter)&&<Tag color="orange">{t("未配置能耗计算源")}</Tag>}{(isNativeEquip(meter)||meter.kind==='nativePoint')&&onAdmit&&<Button disabled={!canWrite} onClick={()=>onAdmit(meter)}>{sourceMeter?t("编辑表计属性"):t("纳入能耗分析")}</Button>}{finLink}</div><p>{t("空间树与 FIN 设备树同步，请在 FIN 中维护；刷新后更新")}</p>{isNativeEquip(meter)&&<p>{t("尚未配置主能耗点，该设备未纳入能耗计算。")}</p>}<Descriptions className="meter-properties" size="small" column={1} items={[
  {key:'path',label:t("FIN 路径"),children:dimensionPath(records,meter.id,'space',true).map(row=>row.name).join(' / ')},
  {key:'dis',label:t("FIN 原始名称"),children:String(meter.nativeDis||meter.name)},{key:'id',label:t("FIN 标识"),children:String(meter.nativeSourceId||meter.id)},
  ...(meter.kind==='nativePoint'?[{key:'unit',label:t("单位"),children:String(meter.unit||'—')},{key:'pointKind',label:t("点类型"),children:String(meter.pointKind||'—')},{key:'his',label:t("历史"),children:meter.his?t("有历史"):t("未启用历史")},{key:'analysis',label:t("分析状态"),children:sourceMeter?t("此点已设为“{0}”的主能耗点，其历史数据用于该设备的能耗计算。",sourceMeter.name):t("未选作能耗计算源")}]:[]),
 ]}/></>;
 const counts=meterDetailCounts(records,meter.id!);
 const relation=(field:string,dimension:Dimension)=>{const row=records.find(item=>item.id===meter[field]);return row?<Button type="link" size="small" onClick={()=>onJump(dimension,row.id!)}>{dimensionPath(records,row.id,dimension).map(item=>item.name).join(' / ')}</Button>:<Typography.Text type="secondary">{t("未配置")}</Typography.Text>;};
 return <><div className="meter-detail-heading">{meter.kind==='totalMeter'?<MeterOriginBadge record={meter}/>:<Tag>{names[meter.kind]}</Tag>}<h3>{meter.name}</h3><Button size="small" disabled={!canWrite} onClick={()=>onEdit(meter)}>{t("编辑表计属性")}</Button>{finLink}</div>{!!meter.configurationError&&<Alert type="error" message={t("能源配置无效，相关统计已阻止")} description={String(meter.configurationError)}/>}<dl className="meter-detail-counts">{[[t("直接下级"),counts.direct],[t("所有下级"),counts.descendants],[t("已绑定点位"),counts.bound],[t("待完成配置"),counts.unfinished]].map(([label,value])=><div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl><p className="meter-detail-hint">{t("统计自身及计量下级；缺少绑定或能源分类的对象计为待完成。")}</p><Descriptions className="meter-properties" size="small" column={1} items={[
  ...(meter.kind==='totalMeter'?[{key:'origin',label:t('表计来源'),children:meterOriginDescription(meterOrigin(meter))},{key:'connector',label:t('来源连接器'),children:meterOrigin(meter).connectorId||'—'}]:[]),
  {key:'space',label:t("计量覆盖范围"),children:relation(meter.spaceId?'spaceId':'nativeSpaceId','space')},{key:'parent',label:t("上级表计"),children:relation('meterParentId','metering')},{key:'organization',label:t("组织归属"),children:relation('organizationId','organization')},
  {key:'category',label:t("能源类型"),children:records.find(row=>row.id===meter.categoryId)?.name||t("未配置")},{key:'usage',label:t("分项"),children:records.find(row=>row.id===meter.utilityId)?.name||t("未配置")},
  {key:'pointName',label:meter.kind==='sensor'?t("FIN 原点名称"):t("主能耗点"),children:<span>{meter.expressionId?t("公式计算"):pointName}{meter.kind!=='sensor'&&!!meter.pointId&&!meter.expressionId&&<EnergySourceBadge meterName={meter.name}/>}</span>},{key:'point',label:t("FIN 点标识"),children:String(meter.pointId||t("未绑定"))},
  {key:'source',label:t("FIN 设备 / 楼层"),children:[point?.equipName,point?.floorName].filter(Boolean).join(' / ')||'—'},
  {key:'site',label:t("FIN 站点"),children:point?.siteName||'—'},{key:'mode',label:t("读数类型"),children:meter.expressionId?t("计算公式"):meter.historyMode==='cumulative'?t("累计读数"):meter.historyMode==='interval'?t("区间用量"):t("依据 FIN 配置")},
  ...(meter.nativeEquip&&meter.kind!=='sensor'?[{key:'currentSource',label:t("当前值来源"),children:meter.autoSum===true?t("分表合计（每 {0} 秒）",meterRollupSeconds(records)):t("原点当前值")}]:[]),
  {key:'included',label:t("计入合计"),children:meter.kind==='sensor'?t("参考量"):meter.includeInTotals===false?t("否"):t("是")},
  {key:'location',label:t("安装位置备注"),children:String(meter.location||'—')},{key:'id',label:t("表计标识"),children:meter.id},
 ]}/></>;
}
