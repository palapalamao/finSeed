import {metricNames,type Metric,type EnerCubixRecord} from './types';
export interface DashboardSlide {id:string;metric:Metric;label:string;categoryId?:string}
export function dashboardSlides(records:EnerCubixRecord[],settings?:EnerCubixRecord):DashboardSlide[]{
 const metrics=(Array.isArray(settings?.visibleMetrics)?settings.visibleMetrics:['energy','cost','coal','co2']) as Metric[];
 const categories=records.filter(record=>record.kind==='category'&&record.id);
 const ids=Array.isArray(settings?.visibleCategoryIds)?settings.visibleCategoryIds as string[]:categories.map(record=>record.id!);
 const slides:DashboardSlide[]=[];
 if(metrics.includes('energy'))ids.forEach(id=>{const category=categories.find(record=>record.id===id);if(category&&!slides.some(slide=>slide.categoryId===id))slides.push({id:`energy:${id}`,metric:'energy',label:category.name,categoryId:id});});
 metrics.filter(metric=>['cost','coal','co2'].includes(metric)).forEach(metric=>{if(!slides.some(slide=>slide.metric===metric))slides.push({id:`metric:${metric}`,metric,label:metricNames[metric]});});
 return slides;
}
export function nextDashboardSlide(slides:DashboardSlide[],currentId?:string):string|undefined{
 if(!slides.length)return undefined;const index=slides.findIndex(slide=>slide.id===currentId);return slides[(index+1)%slides.length].id;
}
