import {Tag,Tooltip} from 'antd';
import {CalculatorOutlined,DashboardOutlined,QuestionCircleOutlined} from '@ant-design/icons';
import type {EnerCubixRecord,ReportSnapshot} from './types';
import {t} from './i18n';
import {meterOrigin,meterOriginDescription,meterOriginLabel,type MeterOrigin} from './meterOrigin';

export function MeterOriginIcon({origin}:{origin:MeterOrigin}){
 return origin.type==='virtual'?<CalculatorOutlined aria-hidden="true"/>:origin.type==='physical'?<DashboardOutlined aria-hidden="true"/>:<QuestionCircleOutlined aria-hidden="true"/>;
}

export function MeterOriginBadge({record}:{record:EnerCubixRecord}){
 if(record.kind!=='totalMeter')return null;
 const origin=meterOrigin(record),label=meterOriginLabel(origin),description=meterOriginDescription(origin);
 return <Tooltip title={description} trigger={['hover','focus']}><Tag className="meter-origin-badge" data-meter-origin={origin.type} color={origin.type==='physical'?'blue':origin.type==='virtual'?'purple':undefined} icon={<MeterOriginIcon origin={origin}/>} aria-label={t('{0}：{1}',label,description)} style={{marginInlineStart:6,marginInlineEnd:0,whiteSpace:'normal'}} tabIndex={0}>{label}</Tag></Tooltip>;
}

export function ReportMeterOriginBadge({snapshot,id}:{snapshot:ReportSnapshot;id:string}){
 const kind=snapshot.display?.meterKinds[id],origin=snapshot.display?.meterOrigins?.[id];
 return kind==='totalMeter'&&origin?<MeterOriginBadge record={{kind,name:snapshot.display?.objects[id]||id,meterOrigin:origin}}/>:null;
}
