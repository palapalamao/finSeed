import {afterEach,beforeAll,describe,expect,it,vi} from 'vitest';
import type {ReportSnapshot} from './types';

afterEach(()=>vi.resetModules());
beforeAll(async()=>{await import('./ReportView');},30000);
function source():ReportSnapshot{
 const from='2026-09-01T00:00:00Z',to='2026-09-03T00:00:00Z';
 return {title:'Profile',project:'test',generatedAt:from,request:{kind:'profile',dimension:'space',spaceSource:'fin',nodeIds:['s'],from,to,metric:'energy',period:'day',perArea:false},result:{kind:'profile',from,to,period:'day',warnings:[],rows:[],summary:{},series:[{id:'s|e',nodeId:'s',name:'Building',unit:'kWh',points:[{ts:from,value:10,quality:'ok',sourceIds:['pt']}]}],extra:{profileDelivery:{mode:'chart',diagnostics:'deferred',snapshotId:'chart-observation'}}}};
}
async function render(snapshot:ReportSnapshot,language:string){
 (await import('./i18n')).initializeLocale(language);
 const [{createElement},{renderToStaticMarkup},{ReportView}]=await Promise.all([import('react'),import('react-dom/server'),import('./ReportView')]);
 return renderToStaticMarkup(createElement(ReportView,{snapshot,onRequireFull:async()=>snapshot}));
}
describe('contribution-scoped profile first chart',()=>{
 it.each(['zh-CN','en-US'])('explains deferred diagnostics and a whole-snapshot rebuild in %s',async language=>{
  const snapshot=source(),before=structuredClone(snapshot),html=await render(snapshot,language);
  expect(html).toContain(language==='zh-CN'?'图表已就绪':'Chart ready');
  expect(html).toContain(language==='zh-CN'?'查看完整诊断':'Read full diagnostics');
  expect(html).toContain(language==='zh-CN'?'重新读取并替换整份快照':'reread and replace the whole snapshot');
  expect(html).not.toContain('chart-observation');
  expect(html).not.toContain('phaseMs');
  expect(html).toContain('report-chart');expect(snapshot).toEqual(before);
 });
 it('retains the normal full-report view',async()=>{
  const snapshot=source();delete snapshot.result.extra!.profileDelivery;
  expect(await render(snapshot,'en-US')).not.toContain('Read full diagnostics');
 });
});
