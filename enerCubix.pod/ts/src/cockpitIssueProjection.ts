import type {CockpitIssue,CockpitSnapshot} from './cockpitTypes';
import {createNavigation,decodeNavigation,encodeNavigation,type CockpitViewState,type NavigationContextV1} from './cockpitNavigation';
export function cockpitIssueNavigation(snapshot:CockpitSnapshot,item:CockpitIssue,view:CockpitViewState):NavigationContextV1|undefined{
 const evidence=item.evidenceTarget?.request;if(!evidence)return;
 const navigation:NavigationContextV1={...createNavigation(snapshot,'profile',view),targetRequest:{kind:'profile',dimension:evidence.dimension,...(evidence.dimension==='space'?{spaceSource:'fin' as const}:{}),nodeIds:[...evidence.nodeIds],categoryId:evidence.categoryIds[0],from:evidence.from,to:evidence.to,asOf:evidence.asOf,period:'hour',metric:'energy',perArea:false}};
 return decodeNavigation(encodeNavigation(navigation),snapshot.context.project);
}
export function cockpitMessageLink(project:string,eventId?:string){return '#/messages?project='+encodeURIComponent(project)+(eventId?'&eventId='+encodeURIComponent(eventId):'');}
