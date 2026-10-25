import {t} from './i18n';
import type {EnerCubixRecord} from './types';

export interface MeterOrigin {
 type:'physical'|'virtual'|'unconfirmed';
 reason:'connector'|'submeterSum'|'expression'|'unconfirmed';
 pointId?:string;connectorId?:string;protocol?:string;
}

export function meterOrigin(record:Pick<EnerCubixRecord,'kind'> & Record<string,unknown>):MeterOrigin{
 if(record.autoSum===true)return {type:'virtual',reason:'submeterSum'};
 if(typeof record.expressionId==='string'&&record.expressionId)return {type:'virtual',reason:'expression'};
 const origin=record.meterOrigin as MeterOrigin|undefined;
 return origin&&['physical','virtual','unconfirmed'].includes(origin.type)?origin:{type:'unconfirmed',reason:'unconfirmed'};
}

export function meterOriginLabel(origin:MeterOrigin):string{
 if(origin.type==='physical')return t('物理总表');
 if(origin.type==='virtual')return t('虚拟总表');
 return t('来源待确认');
}

export function meterOriginDescription(origin:MeterOrigin):string{
 if(origin.reason==='submeterSum')return t('已启用“按分表计算当前值”，当前值由下级表计汇总。');
 if(origin.reason==='expression')return t('当前值通过计算公式生成。');
 if(origin.reason==='connector')return t('主能耗点通过 {0} 连接器采集；清洗和连接状态不改变表计类型。',origin.protocol||t('设备'));
 return t('尚未确认主能耗点的连接器及取值路径，请检查点位来源。');
}
