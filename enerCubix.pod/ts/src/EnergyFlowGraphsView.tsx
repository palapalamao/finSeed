import {EnergyFlowView} from './EnergyFlowView';
import {energyFlowAccounting,energyFlowData} from './energyFlow';
import {locale,t} from './i18n';
import type {ReportSnapshot} from './types';

export function EnergyFlowGraphsView({snapshot,panels,onFocus,exporting}:{snapshot:ReportSnapshot;panels:ReportSnapshot[];onFocus:(graphId:string,id:string)=>void;exporting:boolean}){
 const accounting=energyFlowAccounting(snapshot.result);
 const accountingQuality=accounting&&(({ok:t('完整'),good:t('完整'),derived:t('计算值'),cleaned:t('已清洗'),corrected:t('回绕已修正'),estimated:t('估算值'),filtered:t('有效用量小计'),substituted:t('含替代值'),missing:t('缺测'),na:'NA',incompleteInterval:t('有效用量小计'),overlappingScopes:t('来源重叠')} as Record<string,string>)[accounting.unionQuality]||t('贡献范围无法完整解析'));
 const name=(id:string)=>snapshot.display?.objects[id]||panels.flatMap(panel=>energyFlowData(panel.result)?.nodes||[]).find(node=>(node.nodeId||node.id)===id)?.name||id;
 if(!panels.length)return <section className="energy-flow-empty"><h3>{t('尚无能流数据')}</h3><p>{t('当前服务未返回能流数据，请重新查询。')}</p></section>;
 return <div className="energy-flow-panels">
  {accounting&&<section className="energy-flow-accounting" aria-label={t('范围统计依据')}>
   <p>{t('统计质量：{0}',accountingQuality)}</p>
   {accounting.unionValue!==null&&Number.isFinite(accounting.unionValue)?<><strong>{t('{0}：{1} {2}',accounting.basis==='classificationUnion'?t('分类去重贡献合计'):t('范围去重已有量'),new Intl.NumberFormat(locale,{maximumFractionDigits:2}).format(accounting.unionValue),t(energyFlowData(panels[0].result)?.unit||''))}</strong><p>{t('去重贡献合计按可解析成员的并集计算，不能替代各对象自身归档值。')}</p></>:<p>{t('各对象自身用量独立显示；当前选择没有统一统计边界，不提供混合总计。')}</p>}
   {accounting.sharedMemberIds.length>0&&<><p>{t('共享成员：{0}',accounting.sharedMemberIds.map(name).join('、'))}</p><p>{t('各分类独立保留完整用量，分类之间不能直接相加，也不自动分摊。')}</p></>}
   {accounting.sharedMembers.length>0&&<details><summary>{t('查看共享成员与引用对象')}</summary><ul>{accounting.sharedMembers.map(member=><li key={member.meterId}>{t('{0}：被 {1} 引用',name(member.meterId),member.objectIds.map(name).join('、'))}</li>)}</ul></details>}
  </section>}
  {panels.map(panel=>{const data=energyFlowData(panel.result)!,id=data.graphId||data.objectId||data.focusId;return <EnergyFlowView key={id} snapshot={panel} exporting={exporting} onFocus={focus=>onFocus(id,focus)}/>;})}
 </div>;
}
