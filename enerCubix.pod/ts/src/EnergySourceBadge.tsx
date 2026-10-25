import {Tag,Tooltip} from 'antd';
import {CalculatorOutlined} from '@ant-design/icons';
import {t} from './i18n';

export function EnergySourceBadge({meterName}:{meterName:string}){
 return <Tooltip title={t("此点已设为“{0}”的主能耗点，其历史数据用于该设备的能耗计算。",meterName)}><Tag className="energy-source-badge" color="cyan" icon={<CalculatorOutlined aria-hidden="true"/>} style={{marginInlineStart:6,marginInlineEnd:0,verticalAlign:'middle'}} tabIndex={0}>{t("能耗计算源")}</Tag></Tooltip>;
}
