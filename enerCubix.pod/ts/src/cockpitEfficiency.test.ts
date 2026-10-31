import {filterSnapshot} from './exports';
import {expect,it} from 'vitest';
import raw from '../tests/fixtures/cockpit-efficiency-response.json';
import type {CockpitSnapshot} from './cockpitTypes';
import {cockpitCopSnapshot,cockpitCopNavigation} from './cockpitEfficiencyProjection';
import {decodeNavigation,encodeNavigation,projectCockpitReport} from './cockpitNavigation';
it('preserves total ratio4 rather than averaging hourly8 and2.6667 and projects exact COP report',()=>{
 const source=structuredClone(raw) as unknown as CockpitSnapshot,before=structuredClone(source),item=source.modules.efficiency!.data!.items[0];
 expect(item.numerator.value).toBe(96000);expect(item.denominator.value).toBe(24000);expect(item.ratio.value).toBe(4);
 const report=cockpitCopSnapshot(source,item.configId)!;expect(report.request.nodeIds).toEqual(['cop']);expect(report.result.summary.totals).toMatchObject([{value:4}]);
 const view={selectedFace:'efficiency' as const,presentationMode:false,scrollY:80,draft:{scope:source.context.reportScope,categoryId:source.context.focusCategoryId,preset:'custom' as const}};
 const navigation=cockpitCopNavigation(source,item.configId,view);expect(decodeNavigation(encodeNavigation(navigation),'test')?.selectedFace).toBe('efficiency');expect(projectCockpitReport(source,navigation.targetRequest)?.result).toEqual(report.result);expect(source).toEqual(before);
 expect(filterSnapshot(report,['elec'],['Electricity'])!.result.series).toHaveLength(1);
 expect(projectCockpitReport(source,{...navigation.targetRequest,nodeIds:['unrelated']})).toBeUndefined();
});
