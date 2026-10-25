import {describe,expect,it} from 'vitest';
import {dashboardSlides,nextDashboardSlide} from './dashboard';
import type {EnerCubixRecord} from './types';
const records:EnerCubixRecord[]=[{id:'electric',kind:'category',name:'电力',unit:'kWh'},{id:'water',kind:'category',name:'水量',unit:'m³'}];
describe('configured dashboard cards',()=>{
 it('rotates each visible energy category before enabled cross-category metrics',()=>{const slides=dashboardSlides(records,{kind:'settings',name:'设置',visibleMetrics:['energy','cost','coal','co2'],visibleCategoryIds:['electric','water']});expect(slides.map(slide=>slide.id)).toEqual(['energy:electric','energy:water','metric:cost','metric:coal','metric:co2']);expect(nextDashboardSlide(slides,'energy:electric')).toBe('energy:water');expect(nextDashboardSlide(slides,'energy:water')).toBe('metric:cost');expect(nextDashboardSlide(slides,'metric:co2')).toBe('energy:electric');expect(slides.find(slide=>slide.metric==='cost')).not.toHaveProperty('categoryId');});
 it('honors persisted hidden categories and an explicitly empty category list',()=>{expect(dashboardSlides(records,{kind:'settings',name:'设置',visibleMetrics:['energy','co2'],visibleCategoryIds:['water']}).map(slide=>slide.id)).toEqual(['energy:water','metric:co2']);expect(dashboardSlides(records,{kind:'settings',name:'设置',visibleMetrics:['energy','cost'],visibleCategoryIds:[]}).map(slide=>slide.id)).toEqual(['metric:cost']);expect(dashboardSlides(records).filter(slide=>slide.metric==='energy')).toHaveLength(2);});
});
