import {afterEach,expect,it} from 'vitest';
import type {CockpitSnapshot} from './cockpitTypes';
import {initializeLocale} from './i18n';
import raw from '../tests/fixtures/cockpit-area-response.json';
import {cockpitAreaFormulaText,cockpitAreaStatusText} from './cockpitArea';
afterEach(()=>initializeLocale('zh-CN'));
it('displays the independently expected 300 / 1000 = 0.3 from the actual backend area contract',()=>{
 initializeLocale('en-US');const snapshot=structuredClone(raw) as unknown as CockpitSnapshot,before=structuredClone(snapshot),metric=snapshot.modules.kpis!.data!.values.find(v=>v.id==='areaIntensity')!;
 expect(metric.value).toBe(0.3);expect(metric.details?.areaResolution?.areaM2).toBe(1000);
 expect(metric.details?.areaResolution?.sourceRevisions).toHaveLength(1);
 expect(cockpitAreaFormulaText(metric.details!.formula!)).toBe('300 kWh ÷ 1,000 m² = 0.3 kWh/m²');
 expect(cockpitAreaStatusText(metric.details!.areaResolution!)).toContain('native');expect(snapshot).toEqual(before);
});
it('explains missing and ambiguous denominators without replacing available energy with zero',()=>{
 initializeLocale('en-US');const snapshot=structuredClone(raw) as unknown as CockpitSnapshot,metric=snapshot.modules.kpis!.data!.values.find(v=>v.id==='areaIntensity')!,resolution=metric.details!.areaResolution!;
 expect(cockpitAreaStatusText({...resolution,status:'missingArea',areaM2:null})).toContain('area');
 expect(cockpitAreaStatusText({...resolution,status:'ambiguousArea',areaM2:null})).toContain('boundary');
 expect(cockpitAreaFormulaText({...metric.details!.formula!,value:null,denominator:{...metric.details!.formula!.denominator,value:null}})).toContain('—');
 expect(snapshot.modules.kpis!.data!.values.find(v=>v.id==='energy')?.value).toBe(300);
});
