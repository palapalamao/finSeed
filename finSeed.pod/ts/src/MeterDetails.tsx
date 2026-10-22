import {Button,Descriptions,Empty,Tag,Typography} from 'antd';
import type {Dimension,FinPoint,SeedRecord} from './types';
import {names} from './types';
import {dimensionPath,isNativeSource,meterDetailCounts} from './dimensionTree';
interface Props {meter?:SeedRecord;records:SeedRecord[];point?:FinPoint;canWrite:boolean;onEdit:(record:SeedRecord)=>void;onJump:(dimension:Dimension,id:string)=>void;onAdmit?:(record:SeedRecord)=>void}
export function MeterDetails({meter,records,point,canWrite,onEdit,onJump,onAdmit}:Props){
 if(!meter)return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="选择表计，查看三种归属与来源"/>;
 if(isNativeSource(meter))return <><div className="meter-detail-heading"><Tag>{meter.kind==='nativePoint'?'FIN 原点':'FIN '+String(meter.nativeSourceKind||'空间')}</Tag><h3>{meter.name}</h3>{meter.kind==='nativePoint'&&onAdmit&&<Button disabled={!canWrite} onClick={()=>onAdmit(meter)}>纳入分析</Button>}</div><p>空间树与 FIN 设备树同步，请在 FIN 中维护；刷新后更新</p><Descriptions className="meter-properties" size="small" column={1} items={[
  {key:'path',label:'FIN 路径',children:dimensionPath(records,meter.id,'space',true).map(row=>row.name).join(' / ')},
  {key:'dis',label:'FIN 原始名称',children:String(meter.nativeDis||meter.name)},{key:'id',label:'FIN 标识',children:String(meter.nativeSourceId||meter.id)},
  ...(meter.kind==='nativePoint'?[{key:'unit',label:'单位',children:String(meter.unit||'—')},{key:'pointKind',label:'点类型',children:String(meter.pointKind||'—')},{key:'his',label:'历史',children:meter.his?'有历史':'未启用历史'},{key:'analysis',label:'分析状态',children:'尚未纳入 Seed 计量对象'}]:[]),
 ]}/></>;
 const counts=meterDetailCounts(records,meter.id!);
 const relation=(field:string,dimension:Dimension)=>{const row=records.find(item=>item.id===meter[field]);return row?<Button type="link" size="small" onClick={()=>onJump(dimension,row.id!)}>{dimensionPath(records,row.id,dimension).map(item=>item.name).join(' / ')}</Button>:<Typography.Text type="secondary">未配置</Typography.Text>;};
 return <><div className="meter-detail-heading"><Tag>{names[meter.kind]}</Tag><h3>{meter.name}</h3><Button size="small" disabled={!canWrite} onClick={()=>onEdit(meter)}>编辑表计属性</Button></div><dl className="meter-detail-counts">{[['直接下级',counts.direct],['所有下级',counts.descendants],['已绑定点位',counts.bound],['待完成配置',counts.unfinished]].map(([label,value])=><div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl><p className="meter-detail-hint">统计自身及计量下级；缺少绑定或能源分类的对象计为待完成。</p><Descriptions className="meter-properties" size="small" column={1} items={[
  {key:'space',label:'空间归属',children:relation(meter.nativeSpaceReadonly?'nativeSpaceId':'spaceId','space')},{key:'parent',label:'上级表计',children:relation('meterParentId','metering')},{key:'organization',label:'组织归属',children:relation('organizationId','organization')},
  {key:'category',label:'能源类型',children:records.find(row=>row.id===meter.categoryId)?.name||'未配置'},{key:'usage',label:'分项',children:records.find(row=>row.id===meter.utilityId)?.name||'未配置'},
  {key:'pointName',label:'FIN 原点名称',children:typeof meter.nativeDis==='string'?meter.nativeDis:point?.name||String(meter.pointId||'未绑定')},{key:'point',label:'FIN 点标识',children:String(meter.pointId||'未绑定')},
  {key:'source',label:'FIN 设备 / 楼层',children:[point?.equipName,point?.floorName].filter(Boolean).join(' / ')||'—'},
  {key:'site',label:'FIN 站点',children:point?.siteName||'—'},{key:'mode',label:'读数类型',children:meter.expressionId?'计算公式':meter.historyMode==='cumulative'?'累计读数':meter.historyMode==='interval'?'区间用量':'依据 FIN 配置'},
  {key:'included',label:'计入合计',children:meter.kind==='sensor'?'参考量':meter.includeInTotals===false?'否':'是'},
  {key:'location',label:'安装位置备注',children:String(meter.location||'—')},{key:'id',label:'表计标识',children:meter.id},
 ]}/></>;
}
