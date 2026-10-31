import type {CockpitSnapshot} from './cockpitTypes';
import type {ReportSnapshot} from './types';
import {createNavigation,type CockpitViewState,type NavigationContextV1} from './cockpitNavigation';
export function cockpitCopSnapshot(snapshot:CockpitSnapshot,configId:string):ReportSnapshot|undefined{
 const item=snapshot.modules.efficiency?.data?.items.find(item=>item.configId===configId),raw=item?snapshot.reports[item.reportRef]:undefined;if(!item||!raw)return;
 const c=snapshot.context;return {project:c.project,title:item.name,generatedAt:snapshot.generatedAt,request:{kind:'cop',dimension:'metering',nodeIds:[item.configId],from:item.from,to:item.to,asOf:item.asOf,period:c.time.period,metric:'energy',perArea:false,categoryId:c.focusCategoryId},result:structuredClone(raw)};
}
export function cockpitCopNavigation(snapshot:CockpitSnapshot,configId:string,view:CockpitViewState):NavigationContextV1{
 const report=cockpitCopSnapshot(snapshot,configId);if(!report)throw Error('unavailable_cop_projection');
 return {...createNavigation(snapshot,'profile',view),targetKind:'cop',targetRequest:report.request};
}
