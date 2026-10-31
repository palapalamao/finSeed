import type {CockpitAreaFormula,CockpitAreaResolution} from './cockpitTypes';
import {cockpitAreaFormulaText,cockpitAreaNumber,cockpitAreaStatusText} from './cockpitArea';
import {t} from './i18n';
export function CockpitAreaEvidence({resolution,formula}:{resolution:CockpitAreaResolution;formula?:CockpitAreaFormula}){
 return <section className="cockpit-area-evidence" aria-label={t('统计面积与计算依据')}>
  <p>{cockpitAreaStatusText(resolution)}</p>{formula&&<p className="cockpit-area-formula">{cockpitAreaFormulaText(formula)}</p>}
  <dl><dt>{t('统计面积')}</dt><dd>{cockpitAreaNumber(resolution.areaM2)} m²</dd><dt>{t('用量与面积边界标识')}</dt><dd>{resolution.energyBoundaryId}</dd><dt>{t('服务空间引用')}</dt><dd>{resolution.spaceRefs.join('、')||'—'}</dd><dt>{t('自定义面积边界')}</dt><dd>{resolution.customBoundaryIds.join('、')||'—'}</dd></dl>
  <div className="cockpit-table-scroll"><table><thead><tr><th>{t('面积来源')}</th><th>{t('来源引用')}</th><th>{t('配置版本')}</th><th>{t('原始面积标签')}</th><th>{t('统计面积')}</th></tr></thead><tbody>{resolution.sourceRevisions.map(source=><tr key={source.source+'|'+source.id}><td>{source.name}</td><td>{source.nativeRef||source.id}</td><td>{source.mod||t('版本未提供')}</td><td>{source.nativeArea?`${cockpitAreaNumber(source.nativeArea.value)} ${source.nativeArea.unit||''}`:source.source==='custom'?t('自定义面积'):'—'}</td><td>{cockpitAreaNumber(source.area)} m²</td></tr>)}</tbody></table></div>
  {resolution.excludedOverlaps.length>0&&<ul>{resolution.excludedOverlaps.map((excluded,index)=><li key={index}>{excluded.reasonCode==='duplicateServiceSpace'?t('服务空间 {0} 已去重，仅计一次。',excluded.id):t('空间 {0} 已包含于 {1}，不重复计面积。',excluded.id,excluded.coveredBy)}</li>)}</ul>}
  <p>{t('安装位置不作为计量覆盖范围；本次面积来源随快照保留。')}</p>
 </section>;
}
