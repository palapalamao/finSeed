import {DatePicker,Select} from 'antd';
import dayjs from 'dayjs';
import type {CockpitRequest} from './cockpitTypes';
import {t} from './i18n';

export interface CockpitDateDraft {from?:string;to?:string;period:'hour'|'day'|'month';comparison:NonNullable<CockpitRequest['comparison']>}
export function cockpitComparisonForPreset(comparison:CockpitDateDraft['comparison'],preset:CockpitRequest['time']['preset']):CockpitDateDraft['comparison']{
 return comparison.mode==='previousMonth'&&!['thisMonth','custom'].includes(preset)?{mode:'presetDefault'}:comparison;
}
export function CockpitDates({preset,draft,onChange}:{preset:CockpitRequest['time']['preset'];draft:CockpitDateDraft;onChange:(value:CockpitDateDraft)=>void}){
 const inputZone=Intl.DateTimeFormat().resolvedOptions().timeZone;
 return <>
  {preset==='custom'&&<><label className="cockpit-date-field">{t('查询时间（结束时间不含）')}<DatePicker.RangePicker aria-label={t('驾驶舱自定义区间')} showTime format="YYYY-MM-DD HH:mm:ss" allowClear={false} value={draft.from&&draft.to?[dayjs(draft.from),dayjs(draft.to)]:undefined} onChange={value=>{if(value?.[0]&&value[1])onChange({...draft,from:value[0].format('YYYY-MM-DDTHH:mm:ss.SSSZ'),to:value[1].format('YYYY-MM-DDTHH:mm:ss.SSSZ')});}}/></label><label>{t('汇总间隔')}<Select aria-label={t('汇总间隔')} value={draft.period} onChange={period=>onChange({...draft,period})} options={[{value:'hour',label:t('小时')},{value:'day',label:t('日')},{value:'month',label:t('月')}]}/></label></>}
  <label>{t('同期比较')}<Select aria-label={t('同期比较')} value={draft.comparison.mode} onChange={mode=>onChange({...draft,comparison:{...draft.comparison,mode}})} options={[{value:'presetDefault',label:preset==='custom'?t('自定义区间默认不比较'):preset==='today'?t('默认同刻比较'):t('同比（上年对应区间）')},{value:'previousMonth',label:t('环比（上月对应区间）'),disabled:!['thisMonth','custom'].includes(preset)},{value:'none',label:t('不比较')},{value:'custom',label:t('指定参照区间')}]}/></label>
  {draft.comparison.mode==='previousMonth'&&<p className="cockpit-date-note">{t('环比按 FIN 项目时区前移一个自然月；月中对齐同日同刻，月末不足的日期按月末处理。')}</p>}
  {draft.comparison.mode==='custom'&&<label className="cockpit-date-field">{t('参照区间（结束时间不含）')}<DatePicker.RangePicker aria-label={t('驾驶舱参照区间')} showTime format="YYYY-MM-DD HH:mm:ss" allowClear={false} value={draft.comparison.from&&draft.comparison.to?[dayjs(draft.comparison.from),dayjs(draft.comparison.to)]:undefined} onChange={value=>{if(value?.[0]&&value[1])onChange({...draft,comparison:{mode:'custom',from:value[0].format('YYYY-MM-DDTHH:mm:ss.SSSZ'),to:value[1].format('YYYY-MM-DDTHH:mm:ss.SSSZ')}});}}/></label>}
  {(preset==='custom'||draft.comparison.mode==='custom')&&<p className="cockpit-date-note">{t('日期输入时区：{0}；请求保留绝对时刻，结果按 FIN 项目时区显示。',inputZone)}</p>}
 </>;
}
