import {useMemo} from 'react';
import {ReportChart} from './ReportChart';
import {shareColors,shareName} from './chartOptions';
import {cockpitMetricValue} from './cockpitMetrics';
import type {ReportSnapshot} from './types';
import {locale,t} from './i18n';
import './cockpitShare.css';

/** Same frozen share rows as the table; narrow charts use a wrapping legend. */
export function CockpitShareChart({snapshot,name}:{snapshot:ReportSnapshot;name:(id:string)=>string}){
 const chart=useMemo(()=>({...snapshot,result:{...snapshot.result,extra:{...snapshot.result.extra,utilityShares:snapshot.result.rows}}}),[snapshot]);
 const rows=snapshot.result.rows,colors=shareColors(rows,snapshot.display?.objects);
 return <div className="cockpit-share-chart">
  <ReportChart snapshot={chart} shares compact/>
  <ul className="cockpit-share-legend" aria-label={t('分项能耗占比')}>
   {rows.map((row,index)=>{
    const label=shareName(row,snapshot.display?.objects),value=Object.hasOwn(row,'knownValue')?row.knownValue:row.value;
    const valueType=row.knownValueType??row.valueType;
    const percentage=Object.hasOwn(row,'knownPercentage')?row.knownPercentage:row.percentage;
    return <li key={index}>
     <div className="cockpit-share-heading"><span className="cockpit-share-swatch" aria-hidden="true" style={{background:colors.get(label)}}/><strong className="cockpit-share-name">{label}</strong></div>
     {!!row.nodeId&&<small className="cockpit-share-context">{name(String(row.nodeId))}</small>}
     <dl><div><dt>{t('已有用量')}</dt><dd><span className="cockpit-share-value">{cockpitMetricValue({value:typeof value==='number'?value:null,valueType:valueType==='na'?'na':typeof value==='number'?'number':'null'})}</span> <small>{t(String(row.unit||''))}</small></dd></div><div><dt>{t('占比 (%)')}</dt><dd className="cockpit-share-percentage">{typeof percentage==='number'?new Intl.NumberFormat(locale,{maximumFractionDigits:2}).format(percentage)+'%':'—'}</dd></div></dl>
    </li>;
   })}
  </ul>
 </div>;
}
