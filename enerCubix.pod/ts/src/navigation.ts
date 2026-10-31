import {t,localizedRecord} from './i18n';
import type {ReportKind} from './types';

const groupLabels=localizedRecord(()=>({usage:t('趋势与负荷'),structure:t('构成与排名'),comparison:t('对比分析'),efficiency:t('效率与折算'),diagnostics:t('差额与预测')}));
export const analysisGroups:{key:string;label:string;kinds:ReportKind[]}[]=[
 {key:'usage',get label(){return groupLabels.usage;},kinds:['profile','daily','trend']},
 {key:'structure',get label(){return groupLabels.structure;},kinds:['ranking','proportion','utility','energyFlow']},
 {key:'comparison',get label(){return groupLabels.comparison;},kinds:['comparison']},
 {key:'efficiency',get label(){return groupLabels.efficiency;},kinds:['cop','primary','workingHours','workingDays']},
 {key:'diagnostics',get label(){return groupLabels.diagnostics;},kinds:['leak','forecast']}
];
export const analysisGroup=(kind:ReportKind)=>analysisGroups.find(group=>group.kinds.includes(kind));
