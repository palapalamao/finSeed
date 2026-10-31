import {expect,it} from 'vitest';
import raw from '../tests/fixtures/cockpit-issues-response.json';
import type {CockpitSnapshot} from './cockpitTypes';
import {cockpitIssueNavigation,cockpitMessageLink} from './cockpitIssueProjection';
import {decodeNavigation,encodeNavigation} from './cockpitNavigation';
it('keeps an acknowledged ongoing episode and independent pre-month hour evidence without mutating the parent',()=>{
 const snapshot=structuredClone(raw) as unknown as CockpitSnapshot,before=structuredClone(snapshot),data=snapshot.modules.issues!.data!,item=data.items[0];
 expect(data.activeEventCount).toBe(1);expect(item.acknowledged).toBe(true);expect(item.hourCount).toBe(5);expect(item.active).toBe(true);
 const view={selectedFace:'space' as const,presentationMode:false,scrollY:90,draft:{scope:snapshot.context.reportScope,categoryId:'c',preset:'custom' as const}},navigation=cockpitIssueNavigation(snapshot,item,view)!;
 expect(navigation.targetRequest).toMatchObject({from:'2026-09-30T18:00:00Z',to:'2026-09-30T23:00:00Z',asOf:'2026-10-31T02:00:00Z',period:'hour'});expect(decodeNavigation(encodeNavigation(navigation),'test')?.appliedContext.asOf).toBe(snapshot.context.asOf);expect(cockpitMessageLink('test','event')).toBe('#/messages?project=test&eventId=event');expect(snapshot).toEqual(before);
});
