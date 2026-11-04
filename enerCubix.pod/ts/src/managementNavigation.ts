import {t} from './i18n';

export type ManageView='budgets'|'ruleProfiles'|'spaceAssets'|'tree'|'categories'|'tariffs'|'calendars'|'expressions'|'copConfig'|'templates'|'settings'|'otherSettings'|'bindings'|'tasks';
// Navigation must not import the management page or freeze its initial language.
export const manageTitles:Record<ManageView,string>={
 get budgets(){return t('月度预算配置');},get ruleProfiles(){return t('核查规则配置');},
 get spaceAssets(){return t('空间素材配置');},get tree(){return t('计量对象管理');},
 get categories(){return t('能源分类与分项');},get tariffs(){return t('费率管理');},
 get calendars(){return t('日历与时段');},get expressions(){return t('计算公式');},
 get copConfig(){return t('COP 配置');},get templates(){return t('报表模板');},
 get settings(){return t('概览设置');},get otherSettings(){return t('其他配置');},
 get bindings(){return t('参考点绑定');},get tasks(){return t('计算与报警任务');}
};
