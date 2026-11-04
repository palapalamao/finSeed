import {renderToStaticMarkup} from 'react-dom/server';
import {expect,it} from 'vitest';
import raw from '../tests/fixtures/cockpit-space-response.json';
import {CockpitQuality} from './CockpitQuality';
import type {CockpitSnapshot} from './cockpitTypes';
import {initializeLocale,t} from './i18n';

it.each(['zh-CN','en-US'])('names affected modules and their states before any collapsed details in %s',language=>{
 initializeLocale(language);
 const snapshot=structuredClone(raw) as unknown as CockpitSnapshot;
 Object.values(snapshot.modules).forEach(module=>{module.status='ok';});
 snapshot.modules.time!.status='partial';snapshot.modules.balance!.status='error';snapshot.modules.efficiency!.status='unavailable';
 const before=structuredClone(snapshot),html=renderToStaticMarkup(<CockpitQuality snapshot={snapshot}/>),visible=html.split('<details>')[0];
 for(const text of ['时间','部分数据可用','计量平衡','读取失败','能效','暂不可用'])expect(visible).toContain(t(text));
 expect(html).not.toContain('<details open');expect(snapshot).toEqual(before);
});

it('keeps the healthy summary short without an affected-module list',()=>{
 initializeLocale('en-US');const snapshot=structuredClone(raw) as unknown as CockpitSnapshot;
 Object.values(snapshot.modules).forEach(module=>{module.status='ok';});
 const html=renderToStaticMarkup(<CockpitQuality snapshot={snapshot}/>),visible=html.split('<details>')[0];
 expect(visible).toContain(t('已返回模块均正常。'));expect(visible).not.toContain(t('暂不可用'));expect(html).not.toContain('<details open');
});
