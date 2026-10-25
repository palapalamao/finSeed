import {describe,it,expect} from 'vitest';
import dayjs from 'dayjs';
import {forecastRange,forecastChartOptions} from './forecast';
import type {ReportResult} from './types';
describe('forecast presentation',()=>{
 it('uses completed days and rolling cutoff',()=>{const [from,to]=forecastRange(56,true,dayjs('2001-01-01'),dayjs('2026-10-22T14:30'));expect(to.format('YYYY-MM-DD HH:mm')).toBe('2026-10-22 00:00');expect(to.diff(from,'day')).toBe(56);expect(forecastRange(28,false,dayjs('2026-09-01'),dayjs('2026-10-22'))[1].format('YYYY-MM-DD')).toBe('2026-09-01');});
 it('aligns history and prediction by real dates with distinct bars',()=>{const result:ReportResult={kind:'forecast',from:'',to:'',period:'day',rows:[],warnings:[],summary:{},series:[{id:'m|history',nodeId:'m',name:'表 · 历史',unit:'kWh',role:'history',points:[{ts:'2026-10-21T00:00:00+08:00',value:0,quality:'ok',sourceIds:[]}]},{id:'m|forecast',nodeId:'m',name:'表 · 预测',unit:'kWh',role:'forecast',points:[{ts:'2026-10-22T00:00:00+08:00',value:10,lower:8,upper:12,quality:'predicted',sourceIds:[]}]}]};const option=forecastChartOptions(result,['#123456']) as any;expect(option.series.every((s:any)=>s.type==='bar')).toBe(true);expect(option.series[0].stack).toBe(option.series[1].stack);expect(option.series[0].data[0].value).toBe(0);expect(option.series[1].data[0]).toBeNull();expect(option.series[1].data[1].lower).toBe(8);expect(option.yAxis.scale).toBe(false);});
});
