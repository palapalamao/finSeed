import {t} from './i18n';
import type {ReportKind} from './types';

export const analysisGroups:{key:string;label:string;kinds:ReportKind[]}[]=[
 {key:'usage',label:t('趋势与负荷'),kinds:['profile','daily','trend']},
 {key:'structure',label:t('构成与排名'),kinds:['ranking','proportion','utility']},
 {key:'comparison',label:t('对比分析'),kinds:['comparison']},
 {key:'efficiency',label:t('效率与折算'),kinds:['cop','primary','workingHours','workingDays']},
 {key:'diagnostics',label:t('差额与预测'),kinds:['leak','forecast']}
];
export const analysisGroup=(kind:ReportKind)=>analysisGroups.find(group=>group.kinds.includes(kind));
