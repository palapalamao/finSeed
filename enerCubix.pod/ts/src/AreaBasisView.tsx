import {t} from './i18n';
import {areaBasisRows} from './serviceArea';
import type {ReportSnapshot} from './types';
export function AreaBasisView({snapshot}:{snapshot:ReportSnapshot}){
 const rows=areaBasisRows(snapshot);if(!rows.length)return null;
 return <section className="area-basis"><h3>{t('单位面积计算依据')}</h3><p>{t('使用本次查询时的面积和当前关系；相同服务空间及其包含的楼层只计一次。已有用量不因缺少面积而丢失。')}</p><div className="area-basis-scroll"><table><thead><tr>{[t('统计对象'),t('计算依据'),t('面积来源')].map(label=><th key={label}>{label}</th>)}</tr></thead><tbody>{rows.map((row,index)=><tr key={index}>{row.map((value,column)=><td key={column}>{value}</td>)}</tr>)}</tbody></table></div></section>;
}
