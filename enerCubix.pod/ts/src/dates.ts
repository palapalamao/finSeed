import {t} from './i18n';
import dayjs, {type Dayjs} from 'dayjs';
import type {Preset} from './types';
export const presets:{value:Preset;label:string}[]=[{value:'today',label:t("今日")},{value:'yesterday',label:t("昨日")},{value:'thisWeek',label:t("本周")},{value:'lastWeek',label:t("上周")},{value:'thisMonth',label:t("本月")},{value:'lastMonth',label:t("上月")},{value:'thisYear',label:t("本年")},{value:'lastYear',label:t("上年")}];
export function presetRange(preset:Preset, now:Dayjs=dayjs()):[Dayjs,Dayjs] {
 const weekStart=now.startOf('day').subtract((now.day()+6)%7,'day');
 switch(preset){case 'today':return [now.startOf('day'),now];case 'yesterday':return [now.startOf('day').subtract(1,'day'),now.startOf('day')];case 'thisWeek':return [weekStart,weekStart.add(7,'day')];case 'lastWeek':return [weekStart.subtract(7,'day'),weekStart];case 'thisMonth':return [now.startOf('month'),now.startOf('month').add(1,'month')];case 'lastMonth':return [now.startOf('month').subtract(1,'month'),now.startOf('month')];case 'thisYear':return [now.startOf('year'),now.startOf('year').add(1,'year')];case 'lastYear':return [now.startOf('year').subtract(1,'year'),now.startOf('year')];}
}
export function iso(value:Dayjs){return value.format('YYYY-MM-DDTHH:mm:ssZ');}
export function energyFlowRange(preset:Preset,now:Dayjs=dayjs()):[Dayjs,Dayjs]{
 return preset==='thisMonth'?[now.startOf('month'),now]:presetRange(preset,now);
}
export type OverviewSpan='day'|'month'|'year';
export function overviewRanges(span:OverviewSpan,now:Dayjs=dayjs()):{range:[Dayjs,Dayjs];comparison:[Dayjs,Dayjs]}{
 const previous=span==='day'?now.subtract(1,'day'):now.subtract(1,'year');
 return {range:[now.startOf(span),now],comparison:[previous.startOf(span),previous]};
}
